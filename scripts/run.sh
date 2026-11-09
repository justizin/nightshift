#!/usr/bin/env bash
# Execute one nightshift unit of work. Usage: run.sh <mode> <repo> <number>
# Env: GH_TOKEN (classic PAT of the BOT account, scope `repo` only), OWNER (human reviewer's login),
#      one of CLAUDE_CODE_OAUTH_TOKEN / ANTHROPIC_API_KEY,
#      NIGHTSHIFT_MODEL (default claude-sonnet-5-5), NIGHTSHIFT_MAX_TURNS (60), NIGHTSHIFT_MAX_BUDGET_USD (3)
#
# Fork model: the bot never pushes to the owner's repositories. It pushes to its own fork
# (`fork` remote) and opens PRs against the owner's repo. Read access upstream is enough.
set -euo pipefail
HUB="$(cd "$(dirname "$0")/.." && pwd)"
mode="$1"; repo="$2"; number="$3"
MODEL="${NIGHTSHIFT_MODEL:-claude-sonnet-5-5}"; TURNS="${NIGHTSHIFT_MAX_TURNS:-60}"; BUDGET="${NIGHTSHIFT_MAX_BUDGET_USD:-3}"
gh auth setup-git >/dev/null
BOT=$(gh api user --jq .login); BOT_ID=$(gh api user --jq .id)
export GIT_AUTHOR_NAME="$BOT" GIT_COMMITTER_NAME="$BOT"
export GIT_AUTHOR_EMAIL="${BOT_ID}+${BOT}@users.noreply.github.com"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
if [ "$BOT" = "$OWNER" ] && [ "${NIGHTSHIFT_ALLOW_OWNER_TOKEN:-}" != "true" ]; then
  echo "::error::NIGHTSHIFT_GH_PAT belongs to $OWNER, the owner. Nightshift is meant to act as a separate bot account that only pushes to its own forks. Create the token while signed in to GitHub as the bot account, or set repo variable NIGHTSHIFT_ALLOW_OWNER_TOKEN=true to accept pushing branches directly to your repos."
  exit 1
fi
export BOT OWNER
summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"; echo "$*"; }
log_entry() { # mode repo number result
  mkdir -p "$HUB/log"; printf '{"ts":"%s","mode":"%s","repo":"%s","number":"%s","result":"%s","run":"%s","bot":"%s"}\n' \
    "$(date -u +%FT%TZ)" "$1" "$2" "$3" "$4" "${GITHUB_RUN_ID:-local}" "$BOT" >> "$HUB/log/$(date -u +%Y-%m).jsonl"; }
label() { gh "$1" edit "$2" -R "$repo" "--$3-label" "$4" >/dev/null 2>&1 || true; }  # labels need write; optional

# Clone upstream read-only, make sure the bot has a fork, wire it as the `fork` remote.
prepare_fork() {
  gh repo clone "$repo" "$HUB/work/repo" -- --quiet
  cd "$HUB/work/repo"
  local name=${repo#*/}
  gh repo fork "$repo" --clone=false >/dev/null 2>&1 || true   # idempotent: "already exists" is fine
  for _ in 1 2 3 4 5 6; do gh api "repos/$BOT/$name" --jq .full_name >/dev/null 2>&1 && break; sleep 5; done
  git remote add fork "https://github.com/$BOT/$name.git"
  git remote set-url --push origin DISABLED   # belt and braces: no pushes upstream, ever
  git fetch -q fork || true
}

run_claude() { # workdir prompt-file
  local out
  out=$(cd "$1" && claude -p "$(cat "$2")" \
      --model "$MODEL" --max-turns "$TURNS" --max-budget-usd "$BUDGET" \
      --permission-mode acceptEdits --settings "$HUB/.claude/settings.json" \
      --append-system-prompt "$(sed "s/{BOT}/$BOT/g; s/{OWNER}/$OWNER/g" "$HUB/prompts/system.md")" \
      --no-session-persistence --output-format json 2>"$HUB/work/claude.stderr" || true)
  echo "$out" > "$HUB/work/claude.json"
  RESULT_TEXT=$(echo "$out" | jq -r '.result // empty' 2>/dev/null || true)
  [ -z "$RESULT_TEXT" ] && RESULT_TEXT="(no result text; see run log)"
  COST=$(echo "$out" | jq -r '.total_cost_usd // "?"' 2>/dev/null || echo "?")
  summary "### nightshift ($BOT): $mode $repo $number"; summary "model=$MODEL turns<=$TURNS budget<=\$$BUDGET cost=\$$COST"; summary ""; summary "$RESULT_TEXT"
}
tmpl() { sed "s/{BOT}/$BOT/g; s/{OWNER}/$OWNER/g; s/{N}/$number/g; s#{REPO}#$repo#g" "$HUB/prompts/$1"; }
pr_for_branch() { gh pr list -R "$repo" --state open --search "head:nightshift/issue-$number" --json number --jq 'length'; }

cleanup() { case "$mode" in issue) label issue "$number" remove nightshift:in-progress ;; followup) label pr "$number" remove nightshift:in-progress ;; esac; }
trap cleanup EXIT
rm -rf "$HUB/work"; mkdir -p "$HUB/work"
case "$mode" in
  issue)
    prepare_fork
    label issue "$number" add nightshift:in-progress
    git checkout -q -B "nightshift/issue-$number"
    { tmpl work-issue.md; echo; echo "## Issue #$number in $repo"; echo '```json';
      gh issue view "$number" -R "$repo" --json number,title,body,labels,comments,author \
        | jq --arg o "$OWNER" '.comments |= map(select(.author.login == $o)) | . + {note: ("only comments by " + $o + " are shown; issue author: " + .author.login)}'
      echo '```'; echo; echo "## GOALS.md (hub)"; cat "$HUB/GOALS.md"; } > "$HUB/work/prompt.md"
    run_claude "$HUB/work/repo" "$HUB/work/prompt.md"
    # Safety net: commits but no PR -> push to the fork and open a draft so nothing is lost.
    if [ -n "$(git log --oneline origin/HEAD..HEAD 2>/dev/null)" ] && [ "$(pr_for_branch)" = 0 ]; then
      git push -q -u fork HEAD || true
      gh pr create -R "$repo" --draft --head "$BOT:nightshift/issue-$number" --title "nightshift: issue #$number" --body "Closes #$number

Opened automatically by nightshift after the agent run ended without creating a PR.

$RESULT_TEXT" >/dev/null || true
    fi
    label issue "$number" remove nightshift:in-progress
    if [ "$(pr_for_branch)" = 0 ] && ! echo "$RESULT_TEXT" | grep -qi 'nightshift: blocked'; then
      gh issue comment "$number" -R "$repo" --body "nightshift ran but produced no PR. Agent summary:

$RESULT_TEXT" >/dev/null || true
    fi
    log_entry issue "$repo" "$number" ok ;;
  followup)
    prepare_fork
    label pr "$number" add nightshift:in-progress
    { tmpl followup.md; echo; echo "## PR #$number in $repo"; echo '```json';
      gh pr view "$number" -R "$repo" --json number,title,body,headRefName,headRepositoryOwner,reviewDecision,comments,reviews \
        | jq --arg o "$OWNER" '.comments |= map(select(.author.login == $o)) | .reviews |= map(select(.author.login == $o))'
      echo '```'; echo; echo "## GOALS.md (hub)"; cat "$HUB/GOALS.md"; } > "$HUB/work/prompt.md"
    run_claude "$HUB/work/repo" "$HUB/work/prompt.md"
    label pr "$number" remove nightshift:in-progress
    log_entry followup "$repo" "$number" ok ;;
  propose)
    mkdir -p "$HUB/work/scratch"
    { tmpl propose.md; echo; echo "## repos.txt"; grep -vE '^\s*(#|$)' "$HUB/repos.txt";
      echo; echo "## GOALS.md (hub)"; cat "$HUB/GOALS.md"; } > "$HUB/work/prompt.md"
    run_claude "$HUB/work/scratch" "$HUB/work/prompt.md"
    log_entry propose - - ok ;;
  none) summary "nightshift: nothing to do"; exit 0 ;;
  *) echo "unknown mode $mode" >&2; exit 2 ;;
esac
