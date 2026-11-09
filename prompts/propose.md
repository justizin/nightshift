The nightshift queue is empty. Spend this run finding useful, well-scoped work that advances GOALS.md (appended), and file it as issues for the owner to approve. Do not implement anything.

Steps:
1. For each repository listed in GOALS.md / repos.txt that you can clone with `gh repo clone`, look at: failing or flaky CI on the default branch (`gh run list`), TODO/FIXME comments, stale or wrong documentation, missing tests for recently changed code, outdated dependencies with patch releases, and open issues that lack a clear next step.
2. Pick at most 3 items total across all repos. Each must be something one unattended run could finish and that the owner would plausibly want. Skip anything needing the homelab, credentials, design decisions, or product judgment.
3. For each, check there is no existing open issue or PR for it (`gh issue list --search`, `gh pr list --search`). Then `gh issue create` in that repo with: a precise title, why it matters (one or two sentences citing file paths or run URLs), the proposed change, how to verify it, and labels `nightshift:proposed`. Do NOT add the `nightshift` label; the owner adds that to approve.
4. End with a summary listing the issues you filed (or that nothing qualified and why).
