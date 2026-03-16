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
# Scaffold Cloud Configs
#
# Generates deployment configuration files for Vercel + Supabase Cloud.
# Creates vercel.json, api/index.py adapter, api/requirements.txt,
# updates CORS in backend/main.py, and optionally creates GitHub Actions workflow.
#
# Usage: bash .claude/scripts/scaffold-cloud-configs.sh [--with-github-actions]
# ─────────────────────────────────────────────────────────────

WITH_GH_ACTIONS=false
if [[ "${1:-}" == "--with-github-actions" ]]; then
    WITH_GH_ACTIONS=true
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Scaffold Cloud Configs"
echo "═══════════════════════════════════════════════════════════"
echo ""

CREATED=()

# ── 1. vercel.json ────────────────────────────────────────────

if [ ! -f "vercel.json" ]; then
    cat > vercel.json << 'VJSON'
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "framework": "nuxtjs",
  "buildCommand": "cd frontend && npm run build",
  "outputDirectory": "frontend/.output",
  "functions": {
    "api/**/*.py": {
      "runtime": "@vercel/python@4.3.1",
      "maxDuration": 30
    }
  },
  "rewrites": [
    { "source": "/api/:path*", "destination": "/api/index.py" }
  ],
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "X-Frame-Options", "value": "DENY" },
        { "key": "Strict-Transport-Security", "value": "max-age=31536000; includeSubDomains" },
        { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" },
        { "key": "X-DNS-Prefetch-Control", "value": "on" }
      ]
    }
  ]
}
VJSON
    CREATED+=("vercel.json")
    echo "  Created vercel.json"
else
    echo "  vercel.json already exists — skipped"
fi

# ── 2. api/index.py (FastAPI adapter for Vercel) ─────────────

mkdir -p api

if [ ! -f "api/index.py" ]; then
    cat > api/index.py << 'PYEOF'
"""
Vercel serverless adapter for FastAPI.

This thin wrapper imports the existing FastAPI app from backend/main.py
so Vercel can serve it as a serverless function at /api/*.
Local development (uvicorn) is unchanged — this file is only used by Vercel.
"""
import sys
import os

# Add backend directory to Python path so imports work
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend'))

from main import app  # noqa: E402, F401 — Vercel auto-detects the ASGI app
PYEOF
    CREATED+=("api/index.py")
    echo "  Created api/index.py"
else
    echo "  api/index.py already exists — skipped"
fi

# ── 3. api/requirements.txt ──────────────────────────────────

if [ -f "backend/requirements.txt" ]; then
    cp backend/requirements.txt api/requirements.txt
    CREATED+=("api/requirements.txt")
    echo "  Copied backend/requirements.txt → api/requirements.txt"
else
    echo "  WARNING: backend/requirements.txt not found — api/requirements.txt not created"
fi

# ── 4. Patch backend/main.py CORS for cloud origins ──────────

if [ -f "backend/main.py" ]; then
    if ! grep -q "VERCEL_URL" backend/main.py 2>/dev/null; then
        # Write a patch script that uses .format() for string building
        mkdir -p .claude/tmp
        cat > .claude/tmp/_cors_patch.py << 'PYSCRIPT'
import os

path = "backend/main.py"
with open(path, "r") as f:
    content = f.read()

old_block = '''app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:3000",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)'''

new_block = '''# Build allowed origins list (local dev and cloud)
allowed_origins = [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
]
_vercel_host = os.getenv("VERCEL_URL")
if _vercel_host:
    allowed_origins.append("https://{}".format(_vercel_host))
_prod_host = os.getenv("PRODUCTION_URL")
if _prod_host:
    allowed_origins.append(_prod_host)

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)'''

if old_block in content:
    content = content.replace(old_block, new_block)
    with open(path, "w") as f:
        f.write(content)
    print("  Patched backend/main.py CORS for cloud origins")
else:
    print("  WARNING: Could not find expected CORS block — patch manually")
PYSCRIPT
        "$PYTHON_CMD" .claude/tmp/_cors_patch.py
        rm -f .claude/tmp/_cors_patch.py
    else
        echo "  backend/main.py already has cloud CORS config — skipped"
    fi
else
    echo "  WARNING: backend/main.py not found — CORS not patched"
fi

# ── 5. GitHub Actions workflow (optional) ─────────────────────

if $WITH_GH_ACTIONS; then
    mkdir -p .github/workflows
    if [ ! -f ".github/workflows/deploy.yml" ]; then
        cat > .github/workflows/deploy.yml << 'GHEOF'
name: Deploy to Vercel

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
  VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}

jobs:
  validate-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          cd frontend && npm ci
          cd ../backend && pip install -r requirements.txt -r requirements-dev.txt

      - name: Run pipeline
        run: bash .claude/scripts/run-pipeline.sh team

      - name: Install Vercel CLI
        run: npm install -g vercel

      - name: Deploy to Vercel (Preview)
        if: github.event_name == 'pull_request'
        run: vercel deploy --token=${{ secrets.VERCEL_TOKEN }}

      - name: Deploy to Vercel (Production)
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: vercel deploy --prod --token=${{ secrets.VERCEL_TOKEN }}
GHEOF
        CREATED+=(".github/workflows/deploy.yml")
        echo "  Created .github/workflows/deploy.yml"
    else
        echo "  .github/workflows/deploy.yml already exists — skipped"
    fi
fi

# ── Summary ──────────────────────────────────────────────────

echo ""
if [[ ${#CREATED[@]} -gt 0 ]]; then
    echo "  Created:"
    for item in "${CREATED[@]}"; do
        echo "    + $item"
    done
else
    echo "  All config files already exist — nothing created."
fi
echo ""
echo "  Next: Run 'bash .claude/scripts/deploy-cloud.sh' to deploy."
echo ""
