#!/usr/bin/env bash
# release.sh - bump version and publish waifufetch to GitHub + AUR
#
# Usage: ./release.sh <version>
#   Example: ./release.sh 1.1.0
#
# This script:
#   1. Updates VERSION in waifu, waifufetch, and PKGBUILD (placeholder SHA)
#   2. Commits and pushes the tag to GitHub (so the archive URL is valid)
#   3. Downloads the tarball from GitHub and computes the real SHA256
#   4. Updates PKGBUILD and .SRCINFO with the correct SHA
#   5. Pushes the SHA fix to GitHub + AUR

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <version>"
    echo "  Example: $0 1.1.0"
    exit 1
fi

VERSION="$1"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
AUR_TMP=""

cleanup() {
    [[ -n "$AUR_TMP" && -d "$AUR_TMP" ]] && rm -rf "$AUR_TMP"
}
trap cleanup EXIT

cd "$REPO_DIR"

# ---- Check state ----
if ! git diff --quiet; then
    echo "Error: Working tree has uncommitted changes. Commit or stash first." >&2
    exit 1
fi

if ! git diff --cached --quiet; then
    echo "Error: Staged but uncommitted changes. Commit first." >&2
    exit 1
fi

# ---- Helper: update VERSION in a file ----
update_version_in() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "    (skipped: $file not found)"
        return
    fi
    local current
    current=$(grep -m1 '^[[:space:]]*VERSION="' "$file" 2>/dev/null | sed 's/.*VERSION="\([^"]*\)".*/\1/' || true)
    if [[ -z "$current" ]]; then
        echo "    (skipped: no VERSION= in $file)"
        return
    fi
    if [[ "$current" == "$VERSION" ]]; then
        echo "    Already v$VERSION: $file"
    else
        sed -i "s/^\([[:space:]]*\)VERSION=\"[^\"]*\"/\1VERSION=\"$VERSION\"/" "$file"
        echo "    Updated v$current -> v$VERSION: $file"
    fi
}

# ---- Step 1: Update VERSION and PKGBUILD with placeholder SHA ----
echo "==> Updating VERSION in scripts to v$VERSION..."
update_version_in "waifu"
update_version_in "waifufetch"

echo "==> Updating PKGBUILD to v$VERSION..."
sed -i "s/^pkgver=.*/pkgver=$VERSION/" PKGBUILD
sed -i "s/^pkgrel=.*/pkgrel=1/" PKGBUILD
sed -i "s|/archive/v.*\.tar\.gz|/archive/v$VERSION.tar.gz|" PKGBUILD
# Placeholder SHA -- will be fixed after tag is pushed
sed -i "s/sha256sums=('.*')/sha256sums=('0000000000000000000000000000000000000000000000000000000000000000')/" PKGBUILD

# ---- Step 2: Commit and push tag to GitHub ----
echo "==> Committing release v$VERSION..."
git add PKGBUILD .SRCINFO waifu waifufetch
git commit -m "aur release v$VERSION"

# Remove old tag if it exists
if git rev-parse "v$VERSION" &>/dev/null; then
    echo "Warning: Tag v$VERSION already exists. Overwriting." >&2
    git tag -d "v$VERSION"
fi
git tag "v$VERSION"

echo "==> Pushing to GitHub (origin)..."
git push origin main
git push origin "v$VERSION"

# ---- Step 3: Download tarball from the now-existing tag ----
echo "==> Downloading tarball from GitHub..."
TARBALL="$(mktemp /tmp/waifufetch-XXXXXX.tar.gz 2>/dev/null)"
# Retry a few times in case GitHub CDN hasn't picked up the tag yet
SHA256=""
for attempt in 1 2 3; do
    sleep 2
    curl -sL "https://github.com/JGH0/waifufetch/archive/v$VERSION.tar.gz" -o "$TARBALL"
    if [[ -s "$TARBALL" ]]; then
        SHA256="$(sha256sum "$TARBALL" | cut -d' ' -f1)"
        # Basic sanity: hash should not be all zeros
        if [[ "$SHA256" != "0000000000000000000000000000000000000000000000000000000000000000" ]]; then
            echo "    SHA256 (attempt $attempt): $SHA256"
            break
        fi
    fi
    echo "    Retrying... (attempt $attempt)" >&2
done
rm -f "$TARBALL"

if [[ -z "$SHA256" ]]; then
    echo "Error: Could not download valid tarball from GitHub." >&2
    echo "Check that the tag v$VERSION was pushed correctly." >&2
    exit 1
fi

# ---- Step 4: Regenerate PKGBUILD and .SRCINFO with real SHA ----
echo "==> Updating PKGBUILD with real SHA256..."
sed -i "s/sha256sums=('.*')/sha256sums=('$SHA256')/" PKGBUILD

echo "==> Regenerating .SRCINFO..."
makepkg --printsrcinfo > .SRCINFO

echo "==> Committing SHA fix..."
git add PKGBUILD .SRCINFO
git commit -m "fix SHA256 for v$VERSION"

# ---- Step 5: Push to GitHub ----
echo "==> Pushing SHA fix to GitHub (origin)..."
git push origin main

# ---- Step 6: Push to AUR ----
echo "==> Pushing to AUR..."
AUR_TMP="$(mktemp -d)"
git clone ssh://aur@aur.archlinux.org/waifufetch.git "$AUR_TMP"
cp PKGBUILD .SRCINFO "$AUR_TMP/"
cd "$AUR_TMP"
git add -A
git commit -m "v$VERSION"
git push origin master

echo ""
echo "========================================="
echo "  waifufetch v$VERSION released!"
echo "  GitHub: https://github.com/JGH0/waifufetch"
echo "  AUR:    https://aur.archlinux.org/packages/waifufetch"
echo "========================================="
