#!/usr/bin/env bash
# Decide what this run should do. Prints `mode repo number` and writes the same to $GITHUB_OUTPUT.
#   followup <repo> <pr>     an open nightshift PR the owner commented on or requested changes to
#   issue    <repo> <issue>  the highest-priority open issue labeled `nightshift` with no PR yet
#   propose  - -             queue empty: propose issues from GOALS.md (at most once per day)
#   none     - -             nothing to do
# Needs GH_TOKEN (the PAT), OWNER (GitHub login of the human owner).
set -euo pipefail
cd "$(dirname "$0")/.."
OWNER="${OWNER:?set OWNER to the GitHub login of the human owner}"
repos=$(grep -vE '^\s*(#|$)' repos.txt)
force_mode="${FORCE_MODE:-}"; force_repo="${FORCE_REPO:-}"; force_num="${FORCE_NUMBER:-}"

emit() { echo "$1 $2 $3"; [ -n "${GITHUB_OUTPUT:-}" ] && printf 'mode=%s\nrepo=%s\nnumber=%s\n' "$1" "$2" "$3" >> "$GITHUB_OUTPUT"; exit 0; }

if [ -n "$force_mode" ]; then emit "$force_mode" "${force_repo:--}" "${force_num:--}"; fi

# Preflight: every repo must be reachable with issues readable, or the token is misconfigured.
bad=0
for repo in $repos; do
  if ! gh api "repos/$repo" --jq '.full_name' >/dev/null 2>&1; then echo "::error::cannot read $repo with this token (not in the PAT's repository list, or missing Metadata permission)"; bad=1; continue; fi
  if ! gh issue list -R "$repo" --limit 1 >/dev/null 2>&1; then echo "::error::cannot list issues in $repo (Issues permission missing, or issues disabled)"; bad=1; fi
done
[ "$bad" = 1 ] && { echo "::error::fix NIGHTSHIFT_GH_PAT at https://github.com/settings/personal-access-tokens (select all repos in repos.txt; Contents, Issues, Pull requests, Workflows: read/write)"; exit 1; }

# 1. Follow-ups: owner's review needs answering. Highest value, and it's "a chat" with the owner.
for repo in $repos; do
  pr=$(gh pr list -R "$repo" --state open --search 'head:nightshift/' --limit 30 \
        --json number,reviewDecision,comments,reviews,commits,labels \
        --jq --arg owner "$OWNER" '
          map(select(.labels | map(.name) | index("nightshift:in-progress") | not))
          | map(. as $p
              | ($p.commits | map(.committedDate) | max // "1970") as $last
              | (($p.comments + $p.reviews) | map(select(.author.login == $owner and .submittedAt // .createdAt > $last)) | length) as $new
              | select($p.reviewDecision == "CHANGES_REQUESTED" or $new > 0)
              | .number) | first // empty' 2>/dev/null || true)
  [ -n "$pr" ] && emit followup "$repo" "$pr"
done

# 2. Labeled issues, p1 first, then oldest. Skip ones already in progress, blocked, or with an open PR.
best=""; best_key=""
for repo in $repos; do
  heads=$(gh pr list -R "$repo" --state open --search 'head:nightshift/issue-' --limit 100 --json headRefName --jq '.[].headRefName' 2>/dev/null || true)
  while IFS=$'\t' read -r num created p1; do
    [ -z "$num" ] && continue
    echo "$heads" | grep -qx "nightshift/issue-$num" && continue
    key="$([ "$p1" = true ] && echo 0 || echo 1)-$created"
    if [ -z "$best_key" ] || [[ "$key" < "$best_key" ]]; then best_key="$key"; best="$repo $num"; fi
  done < <(gh issue list -R "$repo" --state open --label nightshift --limit 100 \
            --json number,createdAt,labels \
            --jq '.[] | select(.labels | map(.name) | (index("nightshift:in-progress") or index("nightshift:blocked")) | not)
                  | [.number, .createdAt, (.labels | map(.name) | index("nightshift:p1") != null)] | @tsv' 2>/dev/null || true)
done
[ -n "$best" ] && emit issue $best

# 3. Empty queue: propose work from GOALS.md, but only once per UTC day across all repos.
today=$(date -u +%Y-%m-%d)
for repo in $repos; do
  n=$(gh issue list -R "$repo" --state all --label nightshift:proposed --search "created:>=$today" --limit 5 --json number --jq 'length' 2>/dev/null || echo 0)
  [ "${n:-0}" -gt 0 ] && emit none - -
done
emit propose - -
