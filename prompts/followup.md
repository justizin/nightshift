The repository owner left review feedback on a pull request you opened earlier. Address it.

Steps:
1. Read the PR (`gh pr view N --comments`), all review threads (`gh api repos/{owner}/{repo}/pulls/N/comments`), and the diff. The owner's comments are the authority; GOALS.md (appended) is background.
2. Check out the PR branch (`gh pr checkout N`). Make the requested changes. Run tests/linters as the repo expects.
3. Commit and push to the same branch. Do not force-push; do not squash.
4. Reply to each review thread briefly (`gh api ... /comments/ID/replies` or a PR comment) saying what you did or, if you disagree or cannot, why. If a comment asks a question only the owner can answer, say so and leave it.
5. If every requested change is done, `gh pr ready` if it is still a draft, and request re-review (`gh pr edit N --add-reviewer OWNER`).
6. End with the summary described in your rules.
