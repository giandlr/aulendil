#!/usr/bin/env bash
set -uo pipefail

# write-changelog-entry.sh — Writes dev-log entry, updates CHANGELOG.md,
# and updates deploy-state.json after a successful pipeline run.
#
# Called by run-pipeline.sh ONLY when pipeline passes (exit 0).
# This script must be idempotent — if the current commit hash already
# appears in dev-log.md, it skips without creating a duplicate.
#
# Exit 0 on success or graceful skip. Exit 1 on error (but caller
# should treat this as non-fatal — changelog failure never blocks pipeline).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

DEVLOG_FILE=".claude/dev-log.md"
CHANGELOG_FILE="CHANGELOG.md"
DEPLOY_STATE=".claude/deploy-state.json"
DEVELOPER_CONF=".claude/developer.conf"
TMP_DIR=".claude/tmp"

mkdir -p "$TMP_DIR"

NOW_UTC=$(date -u '+%Y-%m-%d %H:%M:%S')
NOW_ISO=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
NOW_STAMP=$(date -u '+%Y%m%d-%H%M%S')

# ============================================================
# STEP 1 — Resolve author
# ============================================================
AUTHOR_NAME=""
AUTHOR_EMAIL=""
AUTHOR_ROLE=""
AUTHOR_USERNAME="${USER:-unknown}"

# Source developer.conf if it exists
if [[ -f "$DEVELOPER_CONF" ]]; then
    # shellcheck source=/dev/null
    source "$DEVELOPER_CONF" 2>/dev/null || true
    AUTHOR_NAME="${DEVELOPER_NAME:-}"
    AUTHOR_EMAIL="${DEVELOPER_EMAIL:-}"
    AUTHOR_ROLE="${DEVELOPER_ROLE:-}"
fi

# Fallback chain for name
if [[ -z "$AUTHOR_NAME" ]]; then
    AUTHOR_NAME="${GIT_AUTHOR_NAME:-}"
fi
if [[ -z "$AUTHOR_NAME" ]] && command -v git &>/dev/null; then
    AUTHOR_NAME=$(git config user.name 2>/dev/null || echo "")
fi
if [[ -z "$AUTHOR_NAME" ]]; then
    AUTHOR_NAME="$AUTHOR_USERNAME"
fi

# Build display author string
AUTHOR_DISPLAY="$AUTHOR_NAME ($AUTHOR_USERNAME)"
if [[ -n "$AUTHOR_ROLE" ]]; then
    AUTHOR_DISPLAY="$AUTHOR_NAME ($AUTHOR_USERNAME) — $AUTHOR_ROLE"
fi

echo "Changelog author: $AUTHOR_DISPLAY"

# ============================================================
# STEP 2 — Collect git context
# ============================================================
if ! command -v git &>/dev/null || ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    echo "WARNING: Not in a git repository. Skipping changelog entry." >&2
    exit 0
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "0000000")
COMMIT_HASH_FULL=$(git rev-parse HEAD 2>/dev/null || echo "")
COMMIT_MSG=$(git log -1 --format=%s 2>/dev/null || echo "No commit message")
SESSION_ID="${CLAUDE_SESSION_ID:-$(echo "$NOW_STAMP-$COMMIT_HASH" | tr -d ' ')}"

# ============================================================
# IDEMPOTENCY CHECK — skip if this commit already logged
# ============================================================
if [[ -f "$DEVLOG_FILE" ]] && grep -qF "$COMMIT_HASH" "$DEVLOG_FILE" 2>/dev/null; then
    echo "Commit $COMMIT_HASH already in dev-log. Skipping duplicate entry."
    exit 0
fi

# ============================================================
# Collect changed files
# ============================================================
CHANGED_FILES=""
if git rev-parse HEAD~1 &>/dev/null 2>&1; then
    CHANGED_FILES=$(git diff HEAD~1..HEAD --name-status 2>/dev/null || echo "")
else
    # First commit — list all tracked files as Added
    CHANGED_FILES=$(git diff --cached --name-status 2>/dev/null || git ls-files | sed 's/^/A\t/' 2>/dev/null || echo "")
fi

# Build the changed files table
FILES_TABLE=""
while IFS=$'\t' read -r status filepath; do
    [[ -z "$filepath" ]] && continue
    case "$status" in
        A*) change_type="Added" ;;
        M*) change_type="Modified" ;;
        D*) change_type="Deleted" ;;
        R*) change_type="Renamed" ;;
        C*) change_type="Copied" ;;
        *)  change_type="Changed" ;;
    esac
    # Generate a brief summary from the filename
    summary=$(basename "$filepath")
    FILES_TABLE="${FILES_TABLE}| ${filepath} | ${change_type} | ${summary} |
"
done <<< "$CHANGED_FILES"

if [[ -z "$FILES_TABLE" ]]; then
    FILES_TABLE="| (no file changes detected) | — | — |
"
fi

# ============================================================
# STEP 3 — Collect pipeline results
# ============================================================
read_stage_status() {
    local file="$1"
    local default="SKIP"
    if [[ -f "$file" ]]; then
        if command -v jq &>/dev/null; then
            jq -r '.overall_status // "SKIP"' "$file" 2>/dev/null || echo "$default"
        else
            grep -oE '"overall_status"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"/\1/' || echo "$default"
        fi
    else
        echo "$default"
    fi
}

UNIT_STATUS=$(read_stage_status "$TMP_DIR/unit-results.json")
UI_STATUS=$(read_stage_status "$TMP_DIR/ui-results.json")
INTEGRATION_STATUS=$(read_stage_status "$TMP_DIR/integration-results.json")
PERF_STATUS=$(read_stage_status "$TMP_DIR/k6-summary.json")

# Read Opus review
OPUS_DECISION="UNKNOWN"
OPUS_BLOCKERS="?"
OPUS_ADVISORIES="?"
OPUS_TIER1=""
OPUS_TIER2=""
OPUS_PREPROD=""
OPUS_FILE=$(ls -t "$TMP_DIR"/opus-review-*.md 2>/dev/null | head -1)
if [[ -n "$OPUS_FILE" && -f "$OPUS_FILE" ]]; then
    OPUS_DECISION=$(grep -ioE 'Gate:[[:space:]]*(APPROVED WITH CONDITIONS|APPROVED|CHANGES REQUIRED)' "$OPUS_FILE" | head -1 | sed 's/Gate:[[:space:]]*//' | tr -d ' ' || echo "UNKNOWN")
    # Normalize
    if echo "$OPUS_DECISION" | grep -qi "WITH"; then
        OPUS_DECISION="APPROVED WITH CONDITIONS"
    elif echo "$OPUS_DECISION" | grep -qi "CHANGE"; then
        OPUS_DECISION="CHANGES REQUIRED"
    elif echo "$OPUS_DECISION" | grep -qi "APPROVED"; then
        OPUS_DECISION="APPROVED"
    fi
    OPUS_BLOCKERS=$(grep -ioE 'Blockers:[[:space:]]*[0-9]+' "$OPUS_FILE" | head -1 | grep -oE '[0-9]+' || echo "?")
    OPUS_ADVISORIES=$(grep -ioE 'Advisories:[[:space:]]*[0-9]+' "$OPUS_FILE" | head -1 | grep -oE '[0-9]+' || echo "?")
    OPUS_TIER1=$(grep -ioE 'Tier 1 features present:[[:space:]]*[0-9]+[[:space:]]*/[[:space:]]*[0-9]+' "$OPUS_FILE" | head -1 | sed 's/.*: *//' || echo "—")
    OPUS_TIER2=$(grep -ioE 'Tier 2 features present:[[:space:]]*[0-9]+[[:space:]]*/[[:space:]]*[0-9]+' "$OPUS_FILE" | head -1 | sed 's/.*: *//' || echo "—")
    OPUS_PREPROD=$(grep -ioE 'Pre-production items outstanding:[[:space:]]*[0-9]+' "$OPUS_FILE" | head -1 | grep -oE '[0-9]+' || echo "—")
fi

PIPELINE_LOG="$TMP_DIR/pipeline-${NOW_STAMP}.log"
OPUS_REF=""
if [[ -n "$OPUS_FILE" ]]; then
    OPUS_REF=$(basename "$OPUS_FILE")
fi

# ============================================================
# STEP 4 — Change description
# ============================================================
CHANGE_DESC="$COMMIT_MSG"

# If multiple commits since last logged entry, list them
LAST_LOGGED_HASH=""
if [[ -f "$DEVLOG_FILE" ]]; then
    LAST_LOGGED_HASH=$(grep -oE '`[a-f0-9]{7}`' "$DEVLOG_FILE" | head -1 | tr -d '`' 2>/dev/null || echo "")
fi

MULTI_COMMITS=""
if [[ -n "$LAST_LOGGED_HASH" ]] && git rev-parse "$LAST_LOGGED_HASH" &>/dev/null 2>&1; then
    COMMIT_COUNT=$(git rev-list "${LAST_LOGGED_HASH}..HEAD" --count 2>/dev/null || echo "1")
    if [[ "$COMMIT_COUNT" -gt 1 ]]; then
        MULTI_COMMITS=$(git log "${LAST_LOGGED_HASH}..HEAD" --format="- \`%h\` %s" 2>/dev/null || echo "")
        CHANGE_DESC="$COMMIT_COUNT commits in this session:
$MULTI_COMMITS"
    fi
fi

# ============================================================
# STEP 5 — Write dev-log entry
# ============================================================

# Map status to display
status_icon() {
    case "$1" in
        PASS|PASSED) echo "PASSED" ;;
        FAIL|FAILED) echo "FAILED" ;;
        SKIP|SKIPPED) echo "SKIPPED" ;;
        APPROVED) echo "APPROVED" ;;
        "APPROVED WITH CONDITIONS") echo "APPROVED WITH CONDITIONS" ;;
        "CHANGES REQUIRED") echo "CHANGES REQUIRED" ;;
        *) echo "$1" ;;
    esac
}

DEV_LOG_ENTRY="
---
## Session: ${NOW_STAMP}
**Session:** \`${SESSION_ID}\`
**Date:** ${NOW_UTC} UTC
**Author:** ${AUTHOR_DISPLAY}
**Branch:** ${BRANCH}
**Commit:** \`${COMMIT_HASH}\` — \"${COMMIT_MSG}\"

### What Changed
| File | Change Type | Summary |
|------|-------------|---------|
${FILES_TABLE}
### Change Description
${CHANGE_DESC}

### Test Results
| Stage | Status | Detail |
|-------|--------|--------|
| Unit Tests | $(status_icon "$UNIT_STATUS") | See $TMP_DIR/unit-results.json |
| UI Tests | $(status_icon "$UI_STATUS") | See $TMP_DIR/ui-results.json |
| Integration | $(status_icon "$INTEGRATION_STATUS") | See $TMP_DIR/integration-results.json |
| Performance | $(status_icon "$PERF_STATUS") | See $TMP_DIR/k6-summary.json |
| Opus Review | $(status_icon "$OPUS_DECISION") | ${OPUS_BLOCKERS} blockers, ${OPUS_ADVISORIES} advisory |

Full pipeline log: \`.claude/tmp/pipeline-${NOW_STAMP}.log\`
Opus review: \`.claude/tmp/${OPUS_REF}\`

### Opus Review Summary
**Decision:** ${OPUS_DECISION}
**Tier 1 features present:** ${OPUS_TIER1:-—}
**Tier 2 features present:** ${OPUS_TIER2:-—}
**Pre-production items outstanding:** ${OPUS_PREPROD:-—}

### Deployment
**Status:** not-deployed
**Deployed at:** —
**Environment:** —
---"

# Insert after the DEV_LOG_INSERT_POINT marker
if [[ -f "$DEVLOG_FILE" ]]; then
    # Write entry to temp file (awk -v can't handle multi-line strings)
    ENTRY_FILE=$(mktemp)
    printf '%s\n' "$DEV_LOG_ENTRY" > "$ENTRY_FILE"
    TMPFILE=$(mktemp)
    awk -v entryfile="$ENTRY_FILE" '
    {
        print
        if (/<!-- DEV_LOG_INSERT_POINT -->/) {
            while ((getline line < entryfile) > 0) print line
            close(entryfile)
        }
    }' "$DEVLOG_FILE" > "$TMPFILE"
    mv "$TMPFILE" "$DEVLOG_FILE"
    rm -f "$ENTRY_FILE"
    echo "Dev-log entry written for commit $COMMIT_HASH"
else
    echo "WARNING: $DEVLOG_FILE not found. Skipping dev-log entry." >&2
fi

# ============================================================
# STEP 6 — Update CHANGELOG.md Unreleased section
# ============================================================

# Categorize based on conventional commit prefix
CHANGELOG_CATEGORY="Changed"
case "$COMMIT_MSG" in
    feat:*|feat\(*) CHANGELOG_CATEGORY="Added" ;;
    fix:*|fix\(*)   CHANGELOG_CATEGORY="Fixed" ;;
    security:*|security\(*) CHANGELOG_CATEGORY="Security" ;;
    revert:*|remove:*|revert\(*|remove\(*) CHANGELOG_CATEGORY="Removed" ;;
    refactor:*|perf:*|refactor\(*|perf\(*) CHANGELOG_CATEGORY="Changed" ;;
    deprecated:*|deprecate:*) CHANGELOG_CATEGORY="Deprecated" ;;
esac

# Clean commit message (strip conventional prefix for display)
CLEAN_MSG=$(echo "$COMMIT_MSG" | sed 's/^[a-z]*([^)]*): *//' | sed 's/^[a-z]*: *//')
[[ -z "$CLEAN_MSG" ]] && CLEAN_MSG="$COMMIT_MSG"

CHANGELOG_LINE="- [\`${COMMIT_HASH}\`] ${CLEAN_MSG} (${AUTHOR_NAME}, ${BRANCH})"

if [[ -f "$CHANGELOG_FILE" ]]; then
    # Check if a section for this category already exists under Unreleased
    TMPFILE=$(mktemp)

    # Insert the entry after UNRELEASED_INSERT_POINT
    # We'll add the category header and entry
    awk -v line="$CHANGELOG_LINE" -v category="### $CHANGELOG_CATEGORY" '
    {
        print
        if (/<!-- UNRELEASED_INSERT_POINT -->/) {
            print ""
            print category
            print line
        }
    }' "$CHANGELOG_FILE" > "$TMPFILE"
    mv "$TMPFILE" "$CHANGELOG_FILE"
    echo "CHANGELOG.md updated with: $CHANGELOG_LINE"
else
    echo "WARNING: $CHANGELOG_FILE not found. Skipping changelog update." >&2
fi

# ============================================================
# STEP 7 — Update deploy-state.json
# ============================================================

ENTRY_SUMMARY=$(cat <<ENTRY_JSON
{
    "timestamp": "$NOW_ISO",
    "commit": "$COMMIT_HASH",
    "branch": "$BRANCH",
    "author": "$AUTHOR_DISPLAY",
    "message": $(echo "$COMMIT_MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo "\"$COMMIT_MSG\""),
    "pipeline_status": "PASSED",
    "opus_decision": "$OPUS_DECISION",
    "deployment_status": "not-deployed"
}
ENTRY_JSON
)

if command -v jq &>/dev/null && [[ -f "$DEPLOY_STATE" ]]; then
    TMPFILE=$(mktemp)
    jq --arg ts "$NOW_ISO" \
       --arg status "PASSED" \
       --arg opus "$OPUS_DECISION" \
       --argjson entry "$ENTRY_SUMMARY" \
       '.last_pipeline_run = $ts |
        .last_pipeline_status = $status |
        .last_opus_decision = $opus |
        .deployment_status = "not-deployed" |
        .deployed_at = null |
        .entries = ([$entry] + .entries | .[0:10])' \
        "$DEPLOY_STATE" > "$TMPFILE" && mv "$TMPFILE" "$DEPLOY_STATE"
    echo "deploy-state.json updated."
elif [[ -f "$DEPLOY_STATE" ]]; then
    # Fallback without jq: overwrite with minimal state
    cat > "$DEPLOY_STATE" <<DEPLOY_EOF
{
  "last_pipeline_run": "$NOW_ISO",
  "last_pipeline_status": "PASSED",
  "last_opus_decision": "$OPUS_DECISION",
  "deployment_status": "not-deployed",
  "deployed_at": null,
  "deployed_by": null,
  "deployed_version": null,
  "environment": null,
  "entries": [$ENTRY_SUMMARY]
}
DEPLOY_EOF
    echo "deploy-state.json updated (without jq — limited)."
fi

# ============================================================
# STEP 8 — Git commit the changelog files
# ============================================================

# Only commit if in a git repo and there are changes to commit
if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    # Stage only changelog-related files
    git add "$CHANGELOG_FILE" "$DEVLOG_FILE" "$DEPLOY_STATE" 2>/dev/null || true

    # Check if there are staged changes
    if git diff --cached --quiet 2>/dev/null; then
        echo "No changelog changes to commit."
    else
        git commit -m "chore: update changelog [skip ci]" 2>/dev/null || {
            echo "WARNING: Failed to commit changelog update. Files are staged but uncommitted." >&2
        }
        echo "Changelog files committed."
    fi
fi

echo ""
echo "═══ CHANGELOG UPDATE COMPLETE ═══"
echo "  Dev-log:      $DEVLOG_FILE"
echo "  Changelog:    $CHANGELOG_FILE"
echo "  Deploy state: $DEPLOY_STATE"
echo "  Commit:       $COMMIT_HASH"
echo "  Author:       $AUTHOR_DISPLAY"
echo "═════════════════════════════════"
