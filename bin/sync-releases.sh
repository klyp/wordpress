#!/usr/bin/env bash
#
# Build every WordPress release (>= MIN_VERSION) that is not yet a tag on the
# remote, oldest first. Packagist picks up the new tags via its GitHub hook.
#
# Usage: bin/sync-releases.sh [version]
#   With a version, only that release is built.
#
# Env:
#   MIN_VERSION          Oldest release to publish (default: 4.7).
#   DRY_RUN=1            List missing versions only.
#   REMOTE               Remote to compare against / push to (default: origin).

set -euo pipefail

MIN_VERSION="${MIN_VERSION:-4.7}"
DRY_RUN="${DRY_RUN:-0}"
REMOTE="${REMOTE:-origin}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_RE='^[0-9]+\.[0-9]+(\.[0-9]+)?$'

# Prefix each version with a sortable key, e.g. 6.9.9 -> 00006000090000900000 6.9.9
version_key() { awk -F. '{ printf "%05d%05d%05d %s\n", $1, $2, $3, $0 }'; }
sort_versions() { version_key | sort | cut -d' ' -f2; }

if [[ -n "${1:-}" ]]; then
	if [[ ! "$1" =~ $VERSION_RE ]]; then
		echo "Invalid version: $1" >&2
		exit 2
	fi
	missing="$1"
else
	min_key="$(echo "$MIN_VERSION" | version_key | cut -d' ' -f1)"
	released="$(curl -fsS --retry 3 https://api.wordpress.org/core/stable-check/1.0/ |
		jq -r 'keys[]' |
		grep -E "$VERSION_RE" |
		version_key |
		awk -v min="$min_key" '$1 >= min { print $2 }' |
		sort)"
	published="$(git -C "$REPO_ROOT" ls-remote --tags --refs "$REMOTE" |
		sed 's#.*refs/tags/##' |
		sort)"
	missing="$(comm -23 <(echo "$released") <(echo "$published") | sed '/^$/d' | sort_versions)"
fi

if [[ -z "$missing" ]]; then
	echo "Up to date, nothing to build."
	exit 0
fi

echo "Missing versions ($(echo "$missing" | wc -l | tr -d ' ')):"
echo "$missing" | sed 's/^/  /'

if [[ "$DRY_RUN" == 1 ]]; then
	exit 0
fi

built=()
failed=()
for version in $missing; do
	if "$REPO_ROOT/bin/build-release.sh" "$version"; then
		built+=("$version")
	else
		failed+=("$version")
	fi
done

echo "Built: ${built[*]:-none}"
if [[ ${#failed[@]} -gt 0 ]]; then
	echo "Failed: ${failed[*]}" >&2
	exit 1
fi
