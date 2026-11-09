# nightshift

An unattended agent that spends your idle Claude capacity on your own backlog. It runs in GitHub Actions (free on a public repo), picks one unit of work per run from issues you label, and comes back with a pull request. You review in the morning.

## How it decides what to do (scripts/pick.sh)

1. **Follow-ups first.** Any open `nightshift/*` PR where you requested changes or commented after its last commit. Your review is the channel back to it.
2. **Issues you labeled `nightshift`** in any repo in `repos.txt`. `nightshift:p1` first, then oldest.
3. **Its own proposals.** Issues it filed itself, titled `[nightshift proposal]`. It found the work, so it does the work and opens a PR; you never have to label anything. Your review of the PR is the approval. To veto a proposal, close the issue or label it `nightshift:hold`.
4. **Find new work.** Nothing queued: it reads `GOALS.md`, inspects the repos, and files up to 3 proposals, at most once a day. The next run starts on them.
5. Otherwise it exits in a few seconds and costs nothing.

It skips anything in progress, blocked, or already covered by a PR. Self-started work (steps 3 and 4) pauses while `NIGHTSHIFT_MAX_OPEN_PRS` (default 3) of its PRs are waiting for your review, so the pile cannot grow while you are away. Only issues authored by the bot account count as proposals, so nobody else can queue work that way.

## What it may do without you

- Branch, commit, push **to its own fork**, open a **draft** PR against your repo, comment on the issue it worked.
- Ask a question: a comment starting `nightshift: blocked`, then stop. The picker skips it until you reply.
- It never merges. PRs it judges **trivial** (docs, comments, typos, links, dependency patch bumps) are marked ready for review with a `Trivial:` line at the top; everything else stays a draft.
- Never: force-push, rewrite history, close issues/PRs, touch CI workflows unasked, deploy anything. See `.claude/settings.json` (deny list) and `prompts/system.md`.

## Identity and safety model

Nightshift acts as a **separate bot GitHub account** (here `sneakernaut`), not as you. The bot never pushes to your repositories: it pushes to its own forks and opens pull requests against yours. Read access to your repos is all it needs. Consequences:

- Nothing the agent does can delete or rewrite anything you own. Worst case it damages its own fork, which you can delete and re-fork.
- Its PRs show up as from the bot, so your review is a real second pair of eyes.
- Labels on your repos need write access, so they are optional: a blocked task is signalled by an issue comment starting `nightshift: blocked`, and proposals are titled `[nightshift proposal]`.
- The token must be a **classic** PAT with only the `repo` scope. Fine-grained tokens cannot act on repos the bot merely collaborates on. Leave out `delete_repo` (so it cannot delete repositories) and `workflow` (so it cannot edit CI files) unless you want those.

## Setup (once)

1. Push this repo to GitHub as `<you>/nightshift`, public (unlimited Actions minutes). Nothing sensitive lives here.
2. Give the bot account read access to each repo in `repos.txt` (public repos need nothing). Make sure "Allow forking" is on for private ones.
3. Signed in **as the bot**, create a classic PAT at https://github.com/settings/tokens/new with scope `repo` only and an expiry (90 days is sensible). Store it: `gh secret set NIGHTSHIFT_GH_PAT -R <you>/nightshift`.
4. Claude auth, one of:
   - an **API key** in a dedicated Console workspace with a monthly spend limit, as `ANTHROPIC_API_KEY` (recommended: a leak costs at most the cap, and it revokes in one click);
   - or `claude setup-token` and secret `CLAUDE_CODE_OAUTH_TOKEN` (draws on your subscription; a long-lived token for your whole plan).
5. `scripts/labels.sh` creates the labels on every repo in `repos.txt` (run as you, the owner).
6. Optional repo **variables**: `NIGHTSHIFT_MODEL` (default `claude-sonnet-5-5`), `NIGHTSHIFT_MAX_TURNS` (60), `NIGHTSHIFT_MAX_BUDGET_USD` (3, hard stop per run), `NIGHTSHIFT_MAX_RUNS_PER_DAY` (6), `NIGHTSHIFT_MAX_OPEN_PRS` (3), `NIGHTSHIFT_TIMEOUT_MINUTES` (45), `NIGHTSHIFT_ENABLED` (`false` pauses everything).
7. Know where the wall is. On a public repo the bot needs no access at all, so it cannot merge. On a **private repo owned by a personal account**, GitHub gives every collaborator write access, and with no required checks `gh pr merge --auto` merges immediately: that is how a docs PR merged itself on 2026-11-09. The agent is now denied every merge command and the runner fails if a self-merge happens, but those depend on the agent's harness. A wall that does not: a branch rule on `main` requiring a review (GitHub Pro for private repos), or owning the repo from an organization where the bot can hold the read role.

## Feeding it goals

- From GitHub: label an issue `nightshift` (and `nightshift:p1` to jump the queue).
- From a chat with Claude: say "nightshift this" and have it file a labeled issue for you.
- Long-horizon direction: edit `GOALS.md`.
- Review feedback on its PRs is read on the next run.

## Running it by hand

Actions tab, "nightshift", Run workflow. Leave inputs blank to let the picker choose, or force `mode=issue repo=you/repo number=12`.

## Audit trail

Every working run appends a line to `log/YYYY-MM.jsonl` and commits it, which doubles as the activity that keeps GitHub from disabling the schedule after 60 idle days. Agent output is in each run's job summary.
