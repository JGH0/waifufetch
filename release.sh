#!/usr/bin/env bash
# release.sh - bump version and publish waifufetch to GitHub + AUR
#
# Usage: ./release.sh <version>
#   Example: ./release.sh 1.1.0
#
# This script:
#   1. Updates PKGBUILD and .SRCINFO with the new version and SHA256
#   2. Commits the changes
#   3. Creates a git tag
#   4. Pushes to GitHub
#   5. Pushes PKGBUILD + .SRCINFO to AUR

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <version>"
    echo "  Example: $0 1.1.0"
    exit 1
fi

VERSION="$1"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TMPDIR=""
AUR_TMP=""

cleanup() {
    [[ -n "$TMPDIR" && -d "$TMPDIR" ]] && rm -rf "$TMPDIR"
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

# ---- Update PKGBUILD ----
echo "==> Updating PKGBUILD to v$VERSION..."
sed -i "s/^pkgver=.*/pkgver=$VERSION/" PKGBUILD
sed -i "s/^pkgrel=.*/pkgrel=1/" PKGBUILD
sed -i "s|/archive/v.*\.tar\.gz|/archive/v$VERSION.tar.gz|" PKGBUILD

# ---- Download tarball and compute SHA256 ----
echo "==> Downloading tarball from GitHub..."
TMPDIR="$(mktemp -d)"
TARBALL="$TMPDIR/waifufetch-$VERSION.tar.gz"
curl -sL "https://github.com/JGH0/waifufetch/archive/v$VERSION.tar.gz" -o "$TARBALL"
SHA256="$(sha256sum "$TARBALL" | cut -d' ' -f1)"
echo "    SHA256: $SHA256"

sed -i "s/sha256sums=('.*')/sha256sums=('$SHA256')/" PKGBUILD

# ---- Regenerate .SRCINFO ----
echo "==> Regenerating .SRCINFO..."
makepkg --printsrcinfo > .SRCINFO

# ---- Check if version tag already exists ----
if git rev-parse "v$VERSION" &>/dev/null; then
    echo "Warning: Tag v$VERSION already exists. Overwriting." >&2
    git tag -d "v$VERSION"
fi

# ---- Commit and tag ----
echo "==> Committing release v$VERSION..."
git add PKGBUILD .SRCINFO
git commit -m "aur release v$VERSION"
git tag "v$VERSION"

# ---- Push to GitHub ----
echo "==> Pushing to GitHub (origin)..."
git push origin main
git push origin "v$VERSION"

# ---- Push to AUR ----
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
