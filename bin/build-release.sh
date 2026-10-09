#!/usr/bin/env bash
#
# Build one WordPress release as a klyp/wordpress tag.
#
# Downloads the official wordpress.org zip, verifies its sha1, adds a
# composer.json and creates an orphan commit + tag named after the version.
# The tag is then pushed to origin (unless NO_PUSH=1).
#
# Usage: bin/build-release.sh <version>
#
# Env:
#   NO_PUSH=1   Build and tag locally only.
#   REMOTE      Remote to push to (default: origin).

set -euo pipefail

VERSION="${1:-}"
REMOTE="${REMOTE:-origin}"
NO_PUSH="${NO_PUSH:-0}"

INSTALLER_CONSTRAINT='^1.0'

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
	echo "Usage: $0 <version>   (e.g. 6.9.9)" >&2
	exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/$VERSION"
git=(git -C "$REPO_ROOT" -c core.autocrlf=false -c core.excludesFile=/dev/null)

log() { echo "[$VERSION] $*"; }

if [[ "$NO_PUSH" != 1 ]] && "${git[@]}" ls-remote --exit-code --tags "$REMOTE" "refs/tags/$VERSION" >/dev/null 2>&1; then
	log "already published on $REMOTE, skipping (tags are never rewritten)"
	exit 0
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Download + verify.
zip="$BUILD_DIR/wordpress.zip"
log "downloading wordpress-$VERSION.zip"
curl -fsSL --retry 3 -o "$zip" "https://wordpress.org/wordpress-$VERSION.zip"
expected_sha1="$(curl -fsSL --retry 3 "https://wordpress.org/wordpress-$VERSION.zip.sha1" | tr -d '[:space:]')"
actual_sha1="$( (sha1sum "$zip" 2>/dev/null || shasum -a 1 "$zip") | cut -d' ' -f1)"
if [[ -z "$expected_sha1" || "$expected_sha1" != "$actual_sha1" ]]; then
	log "sha1 mismatch: expected '$expected_sha1', got '$actual_sha1'" >&2
	exit 1
fi
log "sha1 ok ($actual_sha1)"

# Extract; the zip has a single top-level wordpress/ directory.
unzip -q "$zip" -d "$BUILD_DIR/extract"
src="$BUILD_DIR/extract/wordpress"
version_php="$src/wp-includes/version.php"
if [[ ! -f "$version_php" ]]; then
	log "wp-includes/version.php not found in zip" >&2
	exit 1
fi

wp_version="$(sed -n "s/^\$wp_version = '\([^']*\)';.*/\1/p" "$version_php")"
php_version="$(sed -n "s/^\$required_php_version = '\([^']*\)';.*/\1/p" "$version_php")"
if [[ "$wp_version" != "$VERSION" ]]; then
	log "version.php says '$wp_version', expected '$VERSION'" >&2
	exit 1
fi
if [[ -z "$php_version" ]]; then
	log "could not read \$required_php_version from version.php" >&2
	exit 1
fi

jq -n \
	--arg version "$VERSION" \
	--arg php ">=$php_version" \
	--arg installer "$INSTALLER_CONSTRAINT" \
	'{
		name: "klyp/wordpress",
		description: "WordPress core, repackaged by Klyp for Composer. Built from the official wordpress.org release zip.",
		type: "wordpress-core",
		keywords: ["wordpress", "cms", "blog"],
		homepage: "https://wordpress.org/",
		license: "GPL-2.0-or-later",
		authors: [{ name: "WordPress Community", homepage: "https://wordpress.org/about/" }],
		support: {
			issues: "https://core.trac.wordpress.org/",
			source: "https://core.trac.wordpress.org/browser",
			docs: "https://developer.wordpress.org/"
		},
		require: {
			php: $php,
			"klyp/wordpress-core-installer": $installer
		},
		provide: { "wordpress/core-implementation": $version }
	}' >"$src/composer.json"

# Commit the extracted tree as an orphan commit, using a throwaway index so the
# checked-out master branch is never touched.
export GIT_INDEX_FILE="$BUILD_DIR/index"
"${git[@]}" --work-tree="$src" add --all --force .
tree="$("${git[@]}" write-tree)"
unset GIT_INDEX_FILE
commit="$("${git[@]}" commit-tree "$tree" -m "WordPress $VERSION")"
"${git[@]}" tag --force "$VERSION" "$commit" >/dev/null
log "tagged $commit (php $php_version)"

if [[ "$NO_PUSH" == 1 ]]; then
	log "NO_PUSH=1, not pushing"
	exit 0
fi

"${git[@]}" push --quiet "$REMOTE" "refs/tags/$VERSION"
log "pushed to $REMOTE"
