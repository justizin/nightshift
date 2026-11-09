# nightshift

An unattended agent that spends your idle Claude capacity on your own backlog. It runs in GitHub Actions (free on a public repo), picks one unit of work per run from issues you label, and comes back with a pull request. You review in the morning.

## How it decides what to do (scripts/pick.sh)

1. **Follow-ups first.** Any open `nightshift/*` PR where you requested changes or commented after its last commit. Your review is the channel back to it.
2. **Labeled issues.** Open issues labeled `nightshift` in any repo in `repos.txt`. `nightshift:p1` first, then oldest. Skips `nightshift:in-progress`, `nightshift:blocked`, and issues that already have a PR.
3. **Propose.** Empty queue: it reads `GOALS.md`, inspects the repos, and files up to 3 issues labeled `nightshift:proposed`. Add the `nightshift` label to approve one. At most once a day.
4. Otherwise it exits in a few seconds and costs nothing.

## What it may do without you

- Branch, commit, push, open a **draft** PR, comment on the issue it worked.
- Ask a question: label `nightshift:blocked` plus a comment, then stop.
- Auto-merge only PRs it classified **trivial** (docs, typos, links, dependency patch bumps) via `gh pr merge --auto --squash`, which only takes effect if the target repo has auto-merge enabled and CI passes. Everything else waits for you.
- Never: force-push, rewrite history, close issues/PRs, touch CI workflows unasked, deploy anything. See `.claude/settings.json` (deny list) and `prompts/system.md`.

## Setup (once)

1. Push this repo to GitHub as `<you>/nightshift`. **Public** means unlimited Actions minutes; private spends your included minutes (about 2,000 min/month on Free). Nothing sensitive lives here: goals are generic, the queue is in each repo's issues.
2. Create a **fine-grained PAT** at https://github.com/settings/personal-access-tokens/new: resource owner = you, repositories = the ones in `repos.txt` (plus this one), permissions: Contents RW, Issues RW, Pull requests RW, Workflows RW, Actions R, Metadata R. Save it as the repo secret `NIGHTSHIFT_GH_PAT`.
3. Claude auth, one of:
   - `claude setup-token` locally (needs a Pro/Max subscription) and save the output as secret `CLAUDE_CODE_OAUTH_TOKEN`. Runs then draw on your subscription's capacity, which is the point.
   - or an API key as `ANTHROPIC_API_KEY` (pay per token).
4. `scripts/labels.sh` creates the labels on every repo in `repos.txt`.
5. Optional repo **variables**: `NIGHTSHIFT_MODEL` (default `claude-sonnet-5-5`), `NIGHTSHIFT_MAX_TURNS` (60), `NIGHTSHIFT_MAX_RUNS_PER_DAY` (6), `NIGHTSHIFT_TIMEOUT_MINUTES` (45), `NIGHTSHIFT_ENABLED` (`false` pauses everything).
6. Enable **auto-merge** in each target repo's settings if you want the trivial-PR path to actually merge.

## Feeding it goals

- From GitHub: label an issue `nightshift` (and `nightshift:p1` to jump the queue).
- From a chat with Claude: say "nightshift this" and have it file a labeled issue for you.
- Long-horizon direction: edit `GOALS.md`.
- Review feedback on its PRs is read on the next run.

## Running it by hand

Actions tab, "nightshift", Run workflow. Leave inputs blank to let the picker choose, or force `mode=issue repo=you/repo number=12`.

## Audit trail

Every working run appends a line to `log/YYYY-MM.jsonl` and commits it, which doubles as the activity that keeps GitHub from disabling the schedule after 60 idle days. Agent output is in each run's job summary.
