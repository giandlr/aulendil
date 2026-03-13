#!/usr/bin/env bash
set -euo pipefail

# mark-deployed.sh — Mark the latest release as deployed to an environment
#
# Usage: bash .claude/scripts/mark-deployed.sh <environment> [version]
#   environment: staging | production | preview
#   version: optional, defaults to latest git tag or "unreleased"
#
# Example: bash .claude/scripts/mark-deployed.sh production v1.0.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

DEPLOY_STATE=".claude/deploy-state.json"
DEVLOG_FILE=".claude/dev-log.md"
DEVELOPER_CONF=".claude/developer.conf"

# ============================================================
# Parse arguments
# ============================================================
ENVIRONMENT="${1:-}"
VERSION="${2:-}"

if [[ -z "$ENVIRONMENT" ]]; then
    echo "Usage: bash .claude/scripts/mark-deployed.sh <environment> [version]" >&2
    echo "  environment: staging | production | preview" >&2
    echo "  version: optional (defaults to latest git tag)" >&2
    exit 1
fi

# Validate environment
case "$ENVIRONMENT" in
    staging|production|preview) ;;
    *)
        echo "WARNING: Non-standard environment '$ENVIRONMENT'. Continuing anyway." >&2
        ;;
esac

# Resolve version
if [[ -z "$VERSION" ]]; then
    if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "unreleased")
    else
        VERSION="unreleased"
    fi
fi

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

NOW_UTC=$(date -u '+%Y-%m-%d %H:%M:%S')
NOW_ISO=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

echo "Marking deployment:"
echo "  Environment: $ENVIRONMENT"
echo "  Version:     $VERSION"
echo "  Author:      $AUTHOR_NAME"
echo "  Timestamp:   $NOW_UTC UTC"
echo ""

# ============================================================
# Update deploy-state.json
# ============================================================
if command -v jq &>/dev/null && [[ -f "$DEPLOY_STATE" ]]; then
    TMPFILE=$(mktemp)
    jq --arg status "deployed" \
       --arg ts "$NOW_ISO" \
       --arg author "$AUTHOR_NAME" \
       --arg env "$ENVIRONMENT" \
       --arg ver "$VERSION" \
       '.deployment_status = $status |
        .deployed_at = $ts |
        .deployed_by = $author |
        .environment = $env |
        .deployed_version = $ver' \
        "$DEPLOY_STATE" > "$TMPFILE" && mv "$TMPFILE" "$DEPLOY_STATE"
    echo "deploy-state.json updated."
elif [[ -f "$DEPLOY_STATE" ]]; then
    cat > "$DEPLOY_STATE" <<DEPLOY_EOF
{
  "last_pipeline_run": null,
  "last_pipeline_status": null,
  "last_opus_decision": null,
  "deployment_status": "deployed",
  "deployed_at": "$NOW_ISO",
  "deployed_by": "$AUTHOR_NAME",
  "deployed_version": "$VERSION",
  "environment": "$ENVIRONMENT",
  "entries": []
}
DEPLOY_EOF
    echo "deploy-state.json updated (without jq)."
fi

# ============================================================
# Update most recent dev-log entry's Deployment section
# ============================================================
if [[ -f "$DEVLOG_FILE" ]]; then
    TMPFILE=$(mktemp)
    # Find the first (most recent) Deployment section and update it
    # We match "**Status:** not-deployed" and replace the block
    awk -v env="$ENVIRONMENT" -v ts="$NOW_UTC UTC" -v status="deployed" '
    BEGIN { updated = 0 }
    /^\*\*Status:\*\* not-deployed/ && updated == 0 {
        print "**Status:** deployed"
        updated = 1
        next
    }
    /^\*\*Deployed at:\*\* —/ && updated == 1 {
        print "**Deployed at:** " ts
        next
    }
    /^\*\*Environment:\*\* —/ && updated == 1 {
        print "**Environment:** " env
        updated = 2
        next
    }
    { print }
    ' "$DEVLOG_FILE" > "$TMPFILE"

    if ! diff -q "$DEVLOG_FILE" "$TMPFILE" &>/dev/null; then
        mv "$TMPFILE" "$DEVLOG_FILE"
        echo "Dev-log entry updated with deployment info."
    else
        rm -f "$TMPFILE"
        echo "No undeployed dev-log entry found to update."
    fi
fi

# ============================================================
# Git commit
# ============================================================
if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    git add "$DEPLOY_STATE" "$DEVLOG_FILE" 2>/dev/null || true

    if ! git diff --cached --quiet 2>/dev/null; then
        git commit -m "chore: mark $VERSION deployed to $ENVIRONMENT" 2>/dev/null || {
            echo "WARNING: Commit failed. Changes are staged." >&2
        }
        echo "Deployment commit created."
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " DEPLOYMENT RECORDED"
echo "═══════════════════════════════════════════════════════════"
echo "  Version:     $VERSION"
echo "  Environment: $ENVIRONMENT"
echo "  Deployed by: $AUTHOR_NAME"
echo "  Deployed at: $NOW_UTC UTC"
echo "═══════════════════════════════════════════════════════════"
