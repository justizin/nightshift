Work the GitHub issue below in this repository, then open a pull request.

Steps:
1. Read the issue, GOALS.md (appended below), and the repository's own agent instructions (CLAUDE.md, AGENTS.md) and tests. Understand how the project is built and tested before changing anything.
2. If the issue is unclear, too large, or needs a decision only the owner can make: do NOT guess. Post one comment on the issue with `gh issue comment` stating the specific question(s), add the label `nightshift:blocked`, and stop.
3. Otherwise implement the smallest complete change that resolves it. Add or update tests when the repo has a test suite. Run the suite (or the relevant part) and the linters.
4. Commit on the current branch (already created for you: `nightshift/issue-N`). Push with `git push -u origin HEAD`.
5. Open a PR with `gh pr create --draft --fill-first` or an explicit title/body. The body must include `Closes #N`, what changed, how you verified it, and what you deliberately left out. Then:
   - If the change is trivial (docs, comments, typos, broken links, dependency patch bump) AND the repo has CI: `gh pr ready`, add label `nightshift:trivial`, then `gh pr merge --auto --squash`. If auto-merge is rejected, leave it ready for review.
   - Otherwise leave it as a draft for the owner.
6. Comment on the issue with one line linking the PR. Remove the `nightshift:in-progress` label (`gh issue edit N --remove-label nightshift:in-progress`).
7. End with the summary described in your rules.
