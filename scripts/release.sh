#!/bin/bash
# Publishes the package to npm, creates a git tag, pushes it, and opens a GitHub release.
#
# Prerequisites:
#   - npm must be logged in (npm whoami)
#   - gh must be authenticated (gh auth status)
#   - Run `npm run changeset:version` and commit the result before running this
#
# Usage:  npm run release

set -euo pipefail

# Ensure we're on main and the working tree is clean
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" ]]; then
  echo "❌  Must be on main branch (currently on '$BRANCH')"
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "❌  Working tree has uncommitted changes – commit or stash them first"
  exit 1
fi

# Publish to npm and create git tag
# changeset publish also runs prepublishOnly (build + checks) via npm publish hooks
npx changeset publish

VERSION=$(node -p "require('./package.json').version")
TAG="v$VERSION"

echo "🏷️   Pushing tag $TAG to origin…"
git push origin "$TAG"
git push origin main

# Extract release notes: text between first "## <version>" and the next "## "
NOTES=$(awk '/^## [0-9]/{if(found) exit; found=1; next} found{print}' CHANGELOG.md | sed -e '/^[[:space:]]*$/d')

echo "🚀  Creating GitHub release $TAG…"
gh release create "$TAG" \
  --title "$TAG" \
  --notes "$NOTES"

echo "✅  Released $TAG"
