# Standing goals

Nightshift reads this file on every run. It is the long-horizon direction that
individual issues don't carry. Keep it short; edit it whenever priorities move.
Nothing here is an instruction to the agent to act outside a labeled issue:
when the queue is empty, nightshift may *propose* issues that advance these
goals (labeled `nightshift:proposed`), never start them unlabeled.

## Priorities, highest first

1. **outpost** stays deployable: CI green, docs match reality, ADRs current.
2. **CareCafe / collab-app**: hardening and tests, never destabilize local or
   domain mode. (Not on GitHub yet; add it to repos.txt once pushed.)
3. **OSX-KVM fleet/**: reproducible macOS guests on Linux hosts.
4. **edge-models**: phased device tiers as listed in its issues.

## Always-welcome work (no issue needed, but still opens a PR)

- Fix a red CI run on `main` in any listed repo.
- Address review comments the owner left on an open `nightshift/*` PR.
- Typos, broken links, stale docs, dependency patch bumps.

## Never

- Touch deployment credentials, Nomad jobs that are running, or anything that
  needs the Tailscale network. The agent runs in GitHub Actions and cannot
  reach the homelab; validate offline only.
- Force-push, rewrite history, close issues, or merge anything. Merging is the
  owner's act.
