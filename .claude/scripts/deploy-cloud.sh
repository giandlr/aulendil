#!/usr/bin/env bash
set -euo pipefail

# Cross-platform Python detection
_find_python() {
    for _py in python3 python py; do
        if command -v "$_py" &>/dev/null; then
            echo "$_py"
            return 0
        fi
    done
    echo ""
}
PYTHON_CMD=$(_find_python)
if [[ -z "$PYTHON_CMD" ]]; then
    echo "ERROR: Python not found. Install Python 3 from https://python.org" >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────
# Deploy Cloud — Orchestrates Vercel deployment
#
# Called AFTER run-pipeline.sh passes. Deploys frontend (Nuxt 3 SSR)
# and backend (FastAPI serverless) to Vercel.
#
# Usage: bash .claude/scripts/deploy-cloud.sh [staging|production]
# ─────────────────────────────────────────────────────────────

ENVIRONMENT="${1:-staging}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Cloud Deploy — $ENVIRONMENT"
echo " $TIMESTAMP"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── 1. Pre-flight checks ─────────────────────────────────────

# Check Vercel CLI
if ! command -v vercel &>/dev/null; then
    echo "  Vercel CLI not found. Installing..."
    npm install -g vercel 2>&1 | tail -3
    if ! command -v vercel &>/dev/null; then
        echo "  ERROR: Failed to install Vercel CLI."
        echo "  Install manually: npm install -g vercel"
        exit 1
    fi
    echo "  Vercel CLI installed."
fi

# Check vercel.json exists
if [ ! -f "vercel.json" ]; then
    echo "  ERROR: vercel.json not found."
    echo "  Run: bash .claude/scripts/scaffold-cloud-configs.sh"
    exit 1
fi

# Check api adapter exists
if [ ! -f "api/index.py" ]; then
    echo "  ERROR: api/index.py not found."
    echo "  Run: bash .claude/scripts/scaffold-cloud-configs.sh"
    exit 1
fi

# Check project is linked
if [ ! -f ".vercel/project.json" ]; then
    echo "  ERROR: Vercel project not linked."
    echo ""
    echo "  To link your project, run:"
    echo "    vercel link"
    echo ""
    echo "  Or ask your IT team to:"
    echo "    1. Create a Vercel team and import this repo"
    echo "    2. Run 'vercel link' in this directory"
    echo ""
    echo "  I can generate a setup guide for your IT team instead."
    echo "  Run: bash .claude/scripts/generate-handoff-doc.sh"
    exit 1
fi

echo "  Pre-flight checks passed."
echo ""

# ── 2. Deploy ────────────────────────────────────────────────

DEPLOY_URL=""
DEPLOY_EXIT=0

if [[ "$ENVIRONMENT" == "production" ]]; then
    echo "  Deploying to production..."
    DEPLOY_OUTPUT=$(vercel deploy --prod --yes 2>&1) || DEPLOY_EXIT=$?
else
    echo "  Deploying to staging (preview)..."
    DEPLOY_OUTPUT=$(vercel deploy --yes 2>&1) || DEPLOY_EXIT=$?
fi

# Extract deployment URL from output
DEPLOY_URL=$(echo "$DEPLOY_OUTPUT" | grep -oE 'https://[a-zA-Z0-9._-]+\.vercel\.app' | head -1 || true)

if [[ $DEPLOY_EXIT -ne 0 ]]; then
    echo ""
    echo "  DEPLOY FAILED"
    echo ""
    echo "$DEPLOY_OUTPUT" | tail -20
    echo ""

    # Update deploy state
    if [ -f ".claude/deploy-state.json" ]; then
        "$PYTHON_CMD" -c "
import json
with open('.claude/deploy-state.json') as f: state = json.load(f)
state['cloud'] = state.get('cloud', {})
state['cloud']['last_deploy_at'] = '$TIMESTAMP'
state['cloud']['last_deploy_status'] = 'failed'
with open('.claude/deploy-state.json', 'w') as f: json.dump(state, f, indent=2); f.write('\n')
"
    fi
    exit 1
fi

echo ""
echo "  Deploy successful!"
echo ""
echo "  $DEPLOY_URL"
echo ""

# ── 3. Update deploy state ───────────────────────────────────

if [ -f ".claude/deploy-state.json" ]; then
    "$PYTHON_CMD" -c "
import json
with open('.claude/deploy-state.json') as f: state = json.load(f)
state['deployment_status'] = 'deployed'
state['deployed_at'] = '$TIMESTAMP'
state['environment'] = '$ENVIRONMENT'
state['cloud'] = state.get('cloud', {})
state['cloud']['provider'] = 'vercel'
state['cloud']['deploy_url'] = '$DEPLOY_URL'
state['cloud']['last_deploy_at'] = '$TIMESTAMP'
state['cloud']['last_deploy_status'] = 'success'
with open('.claude/deploy-state.json', 'w') as f: json.dump(state, f, indent=2); f.write('\n')
"
    echo "  Updated .claude/deploy-state.json"
fi

# ── 4. Verify deployment ─────────────────────────────────────

if [[ -n "$DEPLOY_URL" ]]; then
    echo ""
    echo "  Verifying deployment..."

    # Check frontend
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DEPLOY_URL" 2>/dev/null || echo "000")
    if [[ "$HTTP_STATUS" =~ ^[23] ]]; then
        echo "  Frontend: OK ($HTTP_STATUS)"
    else
        echo "  Frontend: WARNING — returned $HTTP_STATUS (may still be propagating)"
    fi

    # Check API health
    API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DEPLOY_URL/api/health" 2>/dev/null || echo "000")
    if [[ "$API_STATUS" =~ ^[23] ]]; then
        echo "  API /health: OK ($API_STATUS)"
    else
        echo "  API /health: WARNING — returned $API_STATUS (may need env vars configured)"
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Your app is live at $DEPLOY_URL"
echo "═══════════════════════════════════════════════════════════"
echo ""
