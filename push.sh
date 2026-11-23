#!/usr/bin/env bash
# Push TubeFree to a fresh GitHub repo. Run from the repo root.
#   ./push.sh <owner>/<repo>
set -euo pipefail

SLUG="${1:?usage: ./push.sh <owner>/<repo>}"

if [ ! -d .git ]; then
  git init -q -b main
fi

git add -A
git commit -q -m "tubefree: innerTube client, ad-free player, CI ipa build" || true

# gh handles repo creation + remote + push in one shot
if command -v gh >/dev/null 2>&1; then
  gh repo create "$SLUG" --public --source=. --remote=origin --push
else
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/${SLUG}.git"
  git push -u origin main
fi

echo
echo "pushed -> https://github.com/${SLUG}"
echo "actions -> https://github.com/${SLUG}/actions"
