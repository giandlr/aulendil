#!/usr/bin/env bash
set -uo pipefail

# Pre-flight check — validates all prerequisites before bootstrap
# Usage: bash .claude/scripts/preflight-check.sh
# Exit 0 = ready, Exit 1 = blocked

[[ "${AULENDIL_DEBUG:-}" == "1" ]] && set -x

BLOCKERS=()
WARNINGS=()

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " PRE-FLIGHT CHECK"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Node.js
if command -v node &>/dev/null; then
    NODE_VERSION=$(node -v 2>/dev/null | tr -d 'v' | cut -d. -f1)
    if [[ "$NODE_VERSION" -ge 18 ]]; then
        echo "  + Node.js $(node -v)"
    else
        BLOCKERS+=("Node.js 18+ required (found $(node -v)). Update: https://nodejs.org")
    fi
else
    BLOCKERS+=("Node.js not found. Install 18+ from https://nodejs.org")
fi

# Python
PYTHON_CMD=""
for _py in python3 python py; do
    if command -v "$_py" &>/dev/null; then
        PYTHON_CMD="$_py"
        break
    fi
done
if [[ -n "$PYTHON_CMD" ]]; then
    PY_VERSION=$("$PYTHON_CMD" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    echo "  + Python $PY_VERSION"
else
    BLOCKERS+=("Python not found. Install 3.9+ from https://python.org")
fi

# Git
if command -v git &>/dev/null; then
    echo "  + git $(git --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
else
    BLOCKERS+=("git not found. Install from https://git-scm.com")
fi

# Git repo
if git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "  + Inside a git repository"
else
    WARNINGS+=("Not inside a git repository — run 'git init' first")
fi

# Docker (optional)
if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
        echo "  + Docker running"
    else
        WARNINGS+=("Docker installed but not running — Supabase will be skipped during bootstrap")
    fi
else
    WARNINGS+=("Docker not found — Supabase will be skipped during bootstrap (app will run without a database)")
fi

# Disk space (basic check — at least 1GB free)
if command -v df &>/dev/null; then
    FREE_KB=$(df -k . 2>/dev/null | tail -1 | awk '{print $4}')
    if [[ -n "$FREE_KB" && "$FREE_KB" -lt 1048576 ]]; then
        WARNINGS+=("Less than 1GB free disk space — bootstrap may fail during npm install")
    fi
fi

# Port availability
for port in 3000 8000 54321; do
    if command -v lsof &>/dev/null; then
        if lsof -iTCP:"$port" -sTCP:LISTEN &>/dev/null 2>&1; then
            WARNINGS+=("Port $port is already in use — may conflict with dev servers")
        fi
    fi
done

echo ""

# Report
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "  Warnings:"
    for w in "${WARNINGS[@]}"; do
        echo "    ! $w"
    done
    echo ""
fi

if [[ ${#BLOCKERS[@]} -gt 0 ]]; then
    echo "═══════════════════════════════════════════════════════════"
    echo " BLOCKED — ${#BLOCKERS[@]} issue(s) to fix before bootstrap:"
    echo "═══════════════════════════════════════════════════════════"
    for b in "${BLOCKERS[@]}"; do
        echo "  x $b"
    done
    exit 1
fi

echo "═══════════════════════════════════════════════════════════"
echo " READY — all prerequisites met"
echo "═══════════════════════════════════════════════════════════"
exit 0
