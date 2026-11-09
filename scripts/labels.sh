#!/usr/bin/env bash
# Create the nightshift labels on every repo in repos.txt. Idempotent. Needs `gh` logged in.
set -euo pipefail
cd "$(dirname "$0")/.."
mk() { gh label create "$2" -R "$1" --color "$3" --description "$4" --force >/dev/null && echo "  $2"; }
grep -vE '^\s*(#|$)' repos.txt | while read -r repo; do
  echo "$repo"
  mk "$repo" nightshift              5319E7 "Queued for the nightshift agent (it may start this)"
  mk "$repo" nightshift:p1           B60205 "Nightshift picks these first"
  mk "$repo" nightshift:in-progress  FBCA04 "Nightshift is working this right now"
  mk "$repo" nightshift:blocked      D93F0B "Nightshift tried and needs a human decision (see comment)"
  mk "$repo" nightshift:proposed     C5DEF5 "Nightshift proposed this; add 'nightshift' to approve"
  mk "$repo" nightshift:trivial      0E8A16 "Docs/typo/dep-patch PR eligible for auto-merge"
done
