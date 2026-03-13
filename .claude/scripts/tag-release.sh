#!/usr/bin/env bash
set -euo pipefail

# tag-release.sh — Cut a release: rename Unreleased → version, create git tag
#
# Usage: bash .claude/scripts/tag-release.sh v1.0.0
#        bash .claude/scripts/tag-release.sh  (prompts for version)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

CHANGELOG_FILE="CHANGELOG.md"
DEPLOY_STATE=".claude/deploy-state.json"
DEVELOPER_CONF=".claude/developer.conf"

# ============================================================
# Get version number
# ============================================================
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
    echo "Enter the release version (e.g., v1.0.0):"
    read -r VERSION
fi

# Validate semver format
if ! echo "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'; then
    echo "ERROR: Invalid version format '$VERSION'." >&2
    echo "Expected semver format: vX.Y.Z (e.g., v1.0.0, v2.1.3-beta.1)" >&2
    exit 1
fi

echo "Releasing version: $VERSION"
echo ""

# ============================================================
# Resolve author
# ============================================================
AUTHOR_NAME="${USER:-unknown}"
if [[ -f "$DEVELOPER_CONF" ]]; then
    # shellcheck source=/dev/null
    source "$DEVELOPER_CONF" 2>/dev/null || true
    [[ -n "${DEVELOPER_NAME:-}" ]] && AUTHOR_NAME="$DEVELOPER_NAME"
fi
if [[ "$AUTHOR_NAME" == "${USER:-unknown}" ]]; then
    AUTHOR_NAME="${GIT_AUTHOR_NAME:-}"
    [[ -z "$AUTHOR_NAME" ]] && AUTHOR_NAME=$(git config user.name 2>/dev/null || echo "${USER:-unknown}")
fi

# ============================================================
# Check prerequisites
# ============================================================
if ! command -v git &>/dev/null; then
    echo "ERROR: git is not installed." >&2
    exit 1
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    echo "ERROR: Not in a git repository." >&2
    exit 1
fi

if git tag -l "$VERSION" | grep -q .; then
    echo "ERROR: Tag $VERSION already exists." >&2
    exit 1
fi

if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo "ERROR: $CHANGELOG_FILE not found." >&2
    exit 1
fi

# ============================================================
# Update CHANGELOG.md: rename [Unreleased] → [version]
# ============================================================
RELEASE_DATE=$(date -u '+%Y-%m-%d')
TMPFILE=$(mktemp)

awk -v ver="$VERSION" -v date="$RELEASE_DATE" '
/^## \[Unreleased\]/ {
    # Print a new empty Unreleased section
    print "## [Unreleased]"
    print "<!-- UNRELEASED_INSERT_POINT -->"
    print ""
    # Print the version section header
    print "## [" ver "] — " date
    next
}
/<!-- UNRELEASED_INSERT_POINT -->/ {
    # Skip the old insert point (we already printed a new one above)
    next
}
{
    print
}
' "$CHANGELOG_FILE" > "$TMPFILE"

mv "$TMPFILE" "$CHANGELOG_FILE"
echo "CHANGELOG.md: [Unreleased] renamed to [$VERSION] — $RELEASE_DATE"

# ============================================================
# Update deploy-state.json
# ============================================================
NOW_ISO=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

if command -v jq &>/dev/null && [[ -f "$DEPLOY_STATE" ]]; then
    TMPFILE=$(mktemp)
    jq --arg ver "$VERSION" \
       --arg ts "$NOW_ISO" \
       --arg author "$AUTHOR_NAME" \
       '.deployed_version = $ver |
        .deployed_at = $ts |
        .deployed_by = $author' \
        "$DEPLOY_STATE" > "$TMPFILE" && mv "$TMPFILE" "$DEPLOY_STATE"
    echo "deploy-state.json: version set to $VERSION"
elif [[ -f "$DEPLOY_STATE" ]]; then
    # Minimal update without jq — cross-platform sed
    TMPFILE_SED=$(mktemp)
    sed "s/\"deployed_version\":.*/\"deployed_version\": \"$VERSION\",/" "$DEPLOY_STATE" > "$TMPFILE_SED"
    mv "$TMPFILE_SED" "$DEPLOY_STATE"
fi

# ============================================================
# Git commit and tag
# ============================================================
git add "$CHANGELOG_FILE" "$DEPLOY_STATE" 2>/dev/null || true

git commit -m "chore: release $VERSION" 2>/dev/null || {
    echo "WARNING: Commit failed. Changes are staged." >&2
}

git tag -a "$VERSION" -m "Release $VERSION" 2>/dev/null || {
    echo "ERROR: Failed to create tag $VERSION." >&2
    exit 1
}

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " RELEASE $VERSION CREATED"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Changelog:  $CHANGELOG_FILE updated"
echo "  Tag:        $VERSION created"
echo "  Author:     $AUTHOR_NAME"
echo "  Date:       $RELEASE_DATE"
echo ""
echo "  Next steps:"
echo "    git push && git push --tags"
echo ""
echo "═══════════════════════════════════════════════════════════"
