#!/usr/bin/env bash
# Decide what this run should do. Prints `mode repo number` and writes the same to $GITHUB_OUTPUT.
#   followup <repo> <pr>     an open nightshift PR the owner commented on or requested changes to
#   issue    <repo> <issue>  an open issue with no PR yet: owner-labeled `nightshift` first, then the bot's own proposals
#   propose  - -             nothing queued: find new work from GOALS.md and file it (at most once per day)
#   none     - -             nothing to do
# Needs GH_TOKEN (the bot's classic PAT, scope repo), OWNER (GitHub login of the human owner/reviewer).
set -euo pipefail
cd "$(dirname "$0")/.."
OWNER="${OWNER:?set OWNER to the GitHub login of the human owner}"
repos=$(grep -vE '^\s*(#|$)' repos.txt)
force_mode="${FORCE_MODE:-}"; force_repo="${FORCE_REPO:-}"; force_num="${FORCE_NUMBER:-}"

emit() { echo "$1 $2 $3"; [ -n "${GITHUB_OUTPUT:-}" ] && printf 'mode=%s\nrepo=%s\nnumber=%s\n' "$1" "$2" "$3" >> "$GITHUB_OUTPUT"; exit 0; }

# Token sanity: a 401 here means NIGHTSHIFT_GH_PAT is not a valid token (bad paste, revoked, or expired).
if ! who=$(gh api user --jq .login 2>&1); then
  echo "::error::GitHub rejected NIGHTSHIFT_GH_PAT: $who. Re-create a CLASSIC token as the bot account (scope: repo) and store it again with: gh secret set NIGHTSHIFT_GH_PAT -R <owner>/nightshift"; exit 1
fi
echo "acting as $who"
# Preflight: every repo must be reachable with issues readable, or the token is misconfigured.
bad=0
for repo in $repos; do
  if ! gh api "repos/$repo" --jq '.full_name' >/dev/null 2>&1; then echo "::error::cannot read $repo with this token (not in the PAT's repository list, or missing Metadata permission)"; bad=1; continue; fi
  if ! gh issue list -R "$repo" --limit 1 >/dev/null 2>&1; then echo "::error::cannot list issues in $repo (Issues permission missing, or issues disabled)"; bad=1; fi
done
[ "$bad" = 1 ] && { echo "::error::NIGHTSHIFT_GH_PAT must be a CLASSIC token of the bot account with scope repo (fine-grained tokens cannot reach repos the bot only collaborates on); the bot needs at least read access to every repo in repos.txt"; exit 1; }

if [ -n "$force_mode" ]; then emit "$force_mode" "${force_repo:--}" "${force_num:--}"; fi


# 1. Follow-ups: the owner reviewed or commented AFTER the PR's last commit. Once the bot pushes a fix the
#    PR is quiet again until the owner speaks, so one review can never trigger a run twice.
for repo in $repos; do
  pr=$(gh pr list -R "$repo" --state open --search 'head:nightshift/' --limit 30 \
        --json number,reviewDecision,comments,reviews,commits,labels \
        | jq -r --arg owner "$OWNER" '
          map(select(.labels | map(.name) | index("nightshift:in-progress") | not))
          | map(. as $p
              | ($p.commits | map(.committedDate) | max // "1970") as $last
              | (($p.comments + $p.reviews) | map(select(.author.login == $owner and ((.submittedAt // .createdAt) > $last))) | length) as $new
              | select($new > 0)
              | .number) | first // empty' 2>/dev/null || true)
  [ -n "$pr" ] && emit followup "$repo" "$pr"
done

# Helpers shared by steps 2 and 3.
has_pr() {  # repo num -> 0 if a nightshift PR in any state (open, merged, closed) already covers the issue
  gh pr list -R "$1" --state all --search 'head:nightshift/issue-' --limit 200 --json headRefName --jq '.[].headRefName' 2>/dev/null | grep -qx "nightshift/issue-$2"; }
is_blocked() {  # repo num -> 0 if the bot said "nightshift: blocked" and the owner has not replied since
  gh issue view "$2" -R "$1" --json comments 2>/dev/null | jq -r --arg o "$OWNER" '
    (.comments | map(select(.body | ascii_downcase | startswith("nightshift: blocked"))) | last // empty) as $b
    | if $b == null then false else ([.comments[] | select(.author.login == $o and .createdAt > $b.createdAt)] | length == 0) end' 2>/dev/null | grep -qx true; }
SKIP='(index("nightshift:in-progress") or index("nightshift:blocked") or index("nightshift:hold"))'

# 2. Issues the owner labeled `nightshift`: p1 first, then oldest.
best=""; best_key=""
for repo in $repos; do
  while IFS=$'\t' read -r num created p1; do
    [ -z "$num" ] && continue
    has_pr "$repo" "$num" && continue
    is_blocked "$repo" "$num" && continue
    key="$([ "$p1" = true ] && echo 0 || echo 1)-$created"
    if [ -z "$best_key" ] || [[ "$key" < "$best_key" ]]; then best_key="$key"; best="$repo $num"; fi
  done < <(gh issue list -R "$repo" --state open --label nightshift --limit 100 --json number,createdAt,labels \
            | jq -r ".[] | select(.labels | map(.name) | $SKIP | not)
                  | [.number, .createdAt, (.labels | map(.name) | index(\"nightshift:p1\") != null)] | @tsv" 2>/dev/null || true)
done
[ -n "$best" ] && emit issue $best

# Backpressure for self-started work: stop adding to the owner's review pile once it is deep enough.
max_open="${NIGHTSHIFT_MAX_OPEN_PRS:-3}"; open_prs=0
for repo in $repos; do
  n=$(gh pr list -R "$repo" --state open --author "$who" --limit 50 --json number --jq 'length' 2>/dev/null || echo 0)
  open_prs=$((open_prs + ${n:-0}))
done
if [ "$open_prs" -ge "$max_open" ]; then
  echo "$open_prs open nightshift PRs await review (cap $max_open): not starting self-proposed work"; emit none - -
fi

# 3. The bot's own proposals: it found the work, so it does the work. No owner label needed.
#    The owner's review of the PR is the approval. To veto one: close the issue or label it nightshift:hold.
#    Only issues authored by the bot account count, so nobody else can queue work this way.
best=""; best_key=""
for repo in $repos; do
  while IFS=$'\t' read -r num created; do
    [ -z "$num" ] && continue
    has_pr "$repo" "$num" && continue
    is_blocked "$repo" "$num" && continue
    if [ -z "$best_key" ] || [[ "$created" < "$best_key" ]]; then best_key="$created"; best="$repo $num"; fi
  done < <(gh issue list -R "$repo" --state open --author "$who" --limit 100 --json number,createdAt,title,labels \
            | jq -r ".[] | select(.title | startswith(\"[nightshift proposal]\")) | select(.labels | map(.name) | $SKIP | not)
                  | [.number, .createdAt] | @tsv" 2>/dev/null || true)
done
[ -n "$best" ] && emit issue $best

# 4. Nothing queued anywhere: look for new work (GOALS.md), at most once per UTC day.
today=$(date -u +%Y-%m-%d)
for repo in $repos; do
  n=$(gh issue list -R "$repo" --state all --author "$who" --search "created:>=$today" --limit 20 --json title \
        | jq '[.[] | select(.title | startswith("[nightshift proposal]"))] | length' 2>/dev/null || echo 0)
  [ "${n:-0}" -gt 0 ] && { echo "already proposed today in $repo"; emit none - -; }
done
emit propose - -
