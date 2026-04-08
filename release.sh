#!/usr/bin/env bash
set -euo pipefail

# Usage: ./release.sh [major|minor|patch]
# Defaults to patch if no argument given.

BUMP="${1:-patch}"

# Get the latest semver tag
LATEST=$(git tag --sort=-v:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

if [[ -z "$LATEST" ]]; then
    LATEST="0.0.0"
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$LATEST"

case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
    *) echo "Usage: $0 [major|minor|patch]"; exit 1 ;;
esac

NEW_TAG="${MAJOR}.${MINOR}.${PATCH}"

echo "Current version: $LATEST"
echo "New version:     $NEW_TAG"
read -rp "Create and push tag $NEW_TAG? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    exit 0
fi

git tag "$NEW_TAG"
git push origin "$NEW_TAG"

echo "Tag $NEW_TAG pushed. GitHub Actions will handle the release."
