#!/usr/bin/env bash
# Execute one nightshift unit of work. Usage: run.sh <mode> <repo> <number>
# Env: GH_TOKEN (PAT), OWNER, one of CLAUDE_CODE_OAUTH_TOKEN / ANTHROPIC_API_KEY,
#      NIGHTSHIFT_MODEL (default claude-sonnet-5-5), NIGHTSHIFT_MAX_TURNS (default 60)
set -euo pipefail
HUB="$(cd "$(dirname "$0")/.." && pwd)"
mode="$1"; repo="$2"; number="$3"
MODEL="${NIGHTSHIFT_MODEL:-claude-sonnet-5-5}"; TURNS="${NIGHTSHIFT_MAX_TURNS:-60}"; BUDGET="${NIGHTSHIFT_MAX_BUDGET_USD:-3}"
export GIT_AUTHOR_NAME=nightshift GIT_COMMITTER_NAME=nightshift
export GIT_AUTHOR_EMAIL=nightshift@users.noreply.github.com GIT_COMMITTER_EMAIL=nightshift@users.noreply.github.com
gh auth setup-git >/dev/null
summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"; echo "$*"; }
log_entry() { # mode repo number result
  mkdir -p "$HUB/log"; printf '{"ts":"%s","mode":"%s","repo":"%s","number":"%s","result":"%s","run":"%s"}\n' \
    "$(date -u +%FT%TZ)" "$1" "$2" "$3" "$4" "${GITHUB_RUN_ID:-local}" >> "$HUB/log/$(date -u +%Y-%m).jsonl"; }

run_claude() { # workdir prompt-file
  local out
  out=$(cd "$1" && claude -p "$(cat "$2")" \
      --model "$MODEL" --max-turns "$TURNS" --max-budget-usd "$BUDGET" \
      --permission-mode acceptEdits --settings "$HUB/.claude/settings.json" \
      --append-system-prompt "$(cat "$HUB/prompts/system.md")" \
      --no-session-persistence --output-format json 2>"$HUB/work/claude.stderr" || true)
  echo "$out" > "$HUB/work/claude.json"
  RESULT_TEXT=$(echo "$out" | jq -r '.result // empty' 2>/dev/null || true)
  [ -z "$RESULT_TEXT" ] && RESULT_TEXT="(no result text; see run log)"
  COST=$(echo "$out" | jq -r '.total_cost_usd // "?"' 2>/dev/null || echo "?")
  summary "### nightshift: $mode $repo $number"; summary "model=$MODEL turns<=$TURNS budget<=\$$BUDGET cost=\$$COST"; summary ""; summary "$RESULT_TEXT"
}

rm -rf "$HUB/work"; mkdir -p "$HUB/work"
case "$mode" in
  issue)
    gh repo clone "$repo" "$HUB/work/repo" -- --quiet
    cd "$HUB/work/repo"
    gh issue edit "$number" -R "$repo" --add-label nightshift:in-progress >/dev/null
    git checkout -q -B "nightshift/issue-$number"
    { cat "$HUB/prompts/work-issue.md"; echo; echo "## Issue #$number in $repo"; echo '```json';
      gh issue view "$number" -R "$repo" --json number,title,body,labels,comments,author --jq --arg o "$OWNER" '.comments |= map(select(.author.login == $o)) | . + {note: ("only comments by " + $o + " are shown; issue author: " + .author.login)}'; echo '```';
      echo; echo "## GOALS.md (hub)"; cat "$HUB/GOALS.md"; } > "$HUB/work/prompt.md"
    run_claude "$HUB/work/repo" "$HUB/work/prompt.md"
    # Safety net: agent left commits but no PR -> push and open a draft so nothing is lost.
    if [ -n "$(git log --oneline origin/HEAD..HEAD 2>/dev/null)" ] && ! gh pr list -R "$repo" --head "nightshift/issue-$number" --json number --jq 'length' | grep -qv '^0$'; then
      git push -q -u origin HEAD || true
      gh pr create -R "$repo" --draft --title "nightshift: issue #$number" --body "Closes #$number

Opened automatically by nightshift after the agent run ended without creating a PR.

$RESULT_TEXT" >/dev/null || true
    fi
    gh issue edit "$number" -R "$repo" --remove-label nightshift:in-progress >/dev/null || true
    # If no PR exists and the agent didn't mark it blocked, leave its summary on the issue.
    if [ "$(gh pr list -R "$repo" --head "nightshift/issue-$number" --json number --jq 'length')" = 0 ] \
       && ! gh issue view "$number" -R "$repo" --json labels --jq '.labels[].name' | grep -q '^nightshift:blocked$'; then
      gh issue comment "$number" -R "$repo" --body "nightshift ran but produced no PR. Agent summary:

$RESULT_TEXT" >/dev/null || true
    fi
    log_entry issue "$repo" "$number" ok ;;
  followup)
    gh repo clone "$repo" "$HUB/work/repo" -- --quiet
    cd "$HUB/work/repo"
    gh pr edit "$number" -R "$repo" --add-label nightshift:in-progress >/dev/null || true
    { cat "$HUB/prompts/followup.md" | sed "s/OWNER/$OWNER/g; s/ N\b/ $number/g"; echo; echo "## PR #$number in $repo";
      echo '```json'; gh pr view "$number" -R "$repo" --json number,title,body,headRefName,reviewDecision,comments,reviews --jq --arg o "$OWNER" '.comments |= map(select(.author.login == $o)) | .reviews |= map(select(.author.login == $o))'; echo '```';
      echo; echo "## GOALS.md (hub)"; cat "$HUB/GOALS.md"; } > "$HUB/work/prompt.md"
    run_claude "$HUB/work/repo" "$HUB/work/prompt.md"
    gh pr edit "$number" -R "$repo" --remove-label nightshift:in-progress >/dev/null || true
    log_entry followup "$repo" "$number" ok ;;
  propose)
    mkdir -p "$HUB/work/scratch"
    { cat "$HUB/prompts/propose.md"; echo; echo "## repos.txt"; grep -vE '^\s*(#|$)' "$HUB/repos.txt";
      echo; echo "## GOALS.md (hub)"; cat "$HUB/GOALS.md"; } > "$HUB/work/prompt.md"
    run_claude "$HUB/work/scratch" "$HUB/work/prompt.md"
    log_entry propose - - ok ;;
  none) summary "nightshift: nothing to do"; exit 0 ;;
  *) echo "unknown mode $mode" >&2; exit 2 ;;
esac
