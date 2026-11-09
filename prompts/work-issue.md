Work the GitHub issue below in this repository, then open a pull request.

Steps:
1. Read the issue, GOALS.md (appended below), and the repository's own agent instructions (CLAUDE.md, AGENTS.md) and tests. Understand how the project is built and tested before changing anything.
2. If the issue is unclear, too large, or needs a decision only the owner can make: do NOT guess. Post one comment on the issue with `gh issue comment -R {REPO} {N}` that starts with the exact line `nightshift: blocked` followed by your specific question(s); try `gh issue edit {N} -R {REPO} --add-label nightshift:blocked` (it may fail without write access, that is fine), and stop. Your final summary must also start with `nightshift: blocked`.
3. Otherwise implement the smallest complete change that resolves it. Add or update tests when the repo has a test suite. Run the suite (or the relevant part) and the linters.
4. Commit on the current branch (already created for you: `nightshift/issue-{N}`). You are `{BOT}`, working from your own fork: push with `git push -u fork HEAD`. The `origin` remote ({REPO}) is read-only for you; never push there.
5. Open a PR against {REPO} from your fork: `gh pr create -R {REPO} --draft --head {BOT}:nightshift/issue-{N} --title ... --body ...`. The body must include `Closes #{N}`, what changed, how you verified it, and what you deliberately left out. Then:
   - If the change is trivial (docs, comments, typos, broken links, dependency patch bump): `gh pr ready`, and start the PR body with the line `Trivial: <one-line reason>` so the owner can merge it at a glance. Try to add the label `nightshift:trivial`; if that is refused, carry on. Do not merge it.
   - Otherwise leave it as a draft for the owner.
6. Comment on the issue with one line linking the PR.
7. End with the summary described in your rules.
