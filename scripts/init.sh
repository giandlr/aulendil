#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# DEPRECATED — Use bootstrap.sh instead
#
# bootstrap.sh does everything this script does PLUS:
#   - Scaffolds the full Nuxt 3 + FastAPI + Supabase project
#   - Starts all services automatically
#   - Gives you a running app at localhost:3000
#
# Run: bash scripts/bootstrap.sh
# ─────────────────────────────────────────────────────────────

echo ""
echo "  NOTE: init.sh has been replaced by bootstrap.sh"
echo ""
echo "  bootstrap.sh does everything this script does PLUS:"
echo "    - Creates the full project structure (frontend + backend + database)"
echo "    - Installs all dependencies"
echo "    - Starts your app automatically"
echo ""
echo "  Run instead:  bash scripts/bootstrap.sh"
echo ""
echo "  Continuing with legacy setup in 5 seconds... (Ctrl+C to cancel)"
sleep 5
echo ""

# Sprout Init — One-time setup script for new projects
# Reads docs/tech-stack.md to determine what to install
# Works on macOS and Windows (Git Bash / WSL)
# Run from the project root: bash scripts/init.sh

# ============================================================
# Detect platform
# ============================================================
OS_TYPE="unknown"
case "$(uname -s)" in
    Darwin*)  OS_TYPE="macos" ;;
    Linux*)
        if grep -qi microsoft /proc/version 2>/dev/null; then
            OS_TYPE="wsl"
        else
            OS_TYPE="linux"
        fi
        ;;
    MINGW*|MSYS*|CYGWIN*) OS_TYPE="windows" ;;
esac

echo "═══════════════════════════════════════════════════════════"
echo " PROJECT SETUP"
echo " $(date '+%Y-%m-%d %H:%M:%S')  |  Platform: $OS_TYPE"
echo "═══════════════════════════════════════════════════════════"
echo ""

INSTALLED=()
MANUAL_SETUP=()
WARNINGS=()

# Helper: install a package using the appropriate system package manager
sys_install() {
    local pkg="$1"
    local tap="${2:-}"  # optional Homebrew tap

    if [[ "$OS_TYPE" == "macos" ]] && command -v brew &>/dev/null; then
        [[ -n "$tap" ]] && brew install "$tap" 2>&1 | tail -3 || brew install "$pkg" 2>&1 | tail -3
        return $?
    elif [[ "$OS_TYPE" == "windows" || "$OS_TYPE" == "wsl" || "$OS_TYPE" == "linux" ]]; then
        if command -v winget &>/dev/null; then
            winget install --id "$pkg" --accept-package-agreements --accept-source-agreements 2>&1 | tail -3
            return $?
        elif command -v choco &>/dev/null; then
            choco install "$pkg" -y 2>&1 | tail -3
            return $?
        elif command -v scoop &>/dev/null; then
            scoop install "$pkg" 2>&1 | tail -3
            return $?
        elif command -v apt-get &>/dev/null; then
            sudo apt-get install -y "$pkg" 2>&1 | tail -3
            return $?
        fi
    fi
    return 1
}

# ============================================================
# Read tech stack configuration
# ============================================================

TECH_STACK_FILE="docs/tech-stack.md"
if [[ ! -f "$TECH_STACK_FILE" ]]; then
    echo "ERROR: $TECH_STACK_FILE not found. Run this script from the project root." >&2
    exit 1
fi

# Parse key values from tech-stack.md
parse_tech_stack() {
    local key="$1"
    grep -E "^${key}:" "$TECH_STACK_FILE" | head -1 | sed "s/^${key}:\s*//" | tr -d '\r'
}

RUNTIME=$(parse_tech_stack "RUNTIME")
PACKAGE_MANAGER=$(parse_tech_stack "PACKAGE_MANAGER")
FRONTEND_FRAMEWORK=$(parse_tech_stack "FRAMEWORK" | head -1)

echo "Detected tech stack:"
echo "  Runtime:          $RUNTIME"
echo "  Package manager:  $PACKAGE_MANAGER"
echo "  Frontend:         $FRONTEND_FRAMEWORK"
echo ""

# ============================================================
# Create directory structure
# ============================================================

echo "Creating directory structure..."
DIRS=(
    ".claude/agents"
    ".claude/hooks"
    ".claude/scripts"
    ".claude/rules"
    ".claude/reviewers"
    ".claude/tmp"
    "docs"
)

for dir in "${DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        echo "  Created: $dir"
    else
        echo "  Exists:  $dir"
    fi
done
echo ""

# ============================================================
# Make all hook and script files executable
# ============================================================

if [[ "$OS_TYPE" != "windows" ]]; then
    echo "Setting executable permissions..."
    find .claude/hooks -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find .claude/scripts -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find scripts -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    echo "  Done."
else
    echo "Skipping chmod (not needed on Windows)."
fi
echo ""

# ============================================================
# Update .gitignore
# ============================================================

echo "Updating .gitignore..."
GITIGNORE_ENTRIES=(
    ".claude/audit.log"
    ".claude/tmp/"
    "CLAUDE.local.md"
)

touch .gitignore
for entry in "${GITIGNORE_ENTRIES[@]}"; do
    if ! grep -qxF "$entry" .gitignore; then
        echo "$entry" >> .gitignore
        echo "  Added: $entry"
    else
        echo "  Exists: $entry"
    fi
done
echo ""

# ============================================================
# Install Frontend Dependencies (Node.js/TypeScript)
# ============================================================

if [[ -d "frontend" && -f "frontend/package.json" ]]; then
    echo "Installing frontend dev dependencies..."
    if command -v npm &>/dev/null; then
        cd frontend
        npm install --save-dev \
            eslint \
            @typescript-eslint/parser \
            @typescript-eslint/eslint-plugin \
            prettier \
            eslint-config-prettier \
            2>&1 | tail -5
        cd ..
        INSTALLED+=("Frontend ESLint + Prettier + TypeScript plugins")
    else
        WARNINGS+=("npm not found — cannot install frontend dev dependencies")
    fi
    echo ""
elif [[ -d "frontend" ]]; then
    MANUAL_SETUP+=("frontend/package.json not found — run 'cd frontend && npm init' first")
fi

# ============================================================
# Install Python Dependencies
# ============================================================

if [[ "$RUNTIME" == "python" ]] || [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "backend/requirements.txt" ]]; then
    echo "Installing Python dev tools..."

    # Activate virtual env if it exists (bin/ on macOS/Linux, Scripts/ on Windows)
    if [[ -f ".venv/bin/activate" ]]; then
        source .venv/bin/activate
        echo "  Activated virtual environment: .venv"
    elif [[ -f ".venv/Scripts/activate" ]]; then
        source .venv/Scripts/activate
        echo "  Activated virtual environment: .venv"
    elif [[ -f "backend/.venv/bin/activate" ]]; then
        source backend/.venv/bin/activate
        echo "  Activated virtual environment: backend/.venv"
    elif [[ -f "backend/.venv/Scripts/activate" ]]; then
        source backend/.venv/Scripts/activate
        echo "  Activated virtual environment: backend/.venv"
    else
        WARNINGS+=("No virtual environment found. Consider creating one: python -m venv .venv")
    fi

    if command -v pip &>/dev/null; then
        pip install ruff bandit mypy pip-audit 2>&1 | tail -5
        INSTALLED+=("Python tools: ruff, bandit, mypy, pip-audit")
    elif command -v pip3 &>/dev/null; then
        pip3 install ruff bandit mypy pip-audit 2>&1 | tail -5
        INSTALLED+=("Python tools: ruff, bandit, mypy, pip-audit")
    else
        WARNINGS+=("pip not found — cannot install Python dev tools")
    fi
    echo ""
fi

# ============================================================
# Auto-install external tools
# ============================================================

echo "Checking and installing external tools..."

# gitleaks
if command -v gitleaks &>/dev/null; then
    echo "  ✓ gitleaks $(gitleaks version 2>/dev/null || echo 'installed')"
    INSTALLED+=("gitleaks (secret scanning)")
else
    echo "  Installing gitleaks..."
    if sys_install "gitleaks" ""; then
        INSTALLED+=("gitleaks (secret scanning)")
    else
        WARNINGS+=("Cannot auto-install gitleaks. Install manually: https://github.com/gitleaks/gitleaks#installing")
    fi
fi

# k6
if command -v k6 &>/dev/null; then
    echo "  ✓ k6 $(k6 version 2>/dev/null | head -1 || echo 'installed')"
    INSTALLED+=("k6 (load testing)")
else
    echo "  Installing k6..."
    if sys_install "k6" ""; then
        INSTALLED+=("k6 (load testing)")
    else
        WARNINGS+=("Cannot auto-install k6. Install manually: https://k6.io/docs/get-started/installation/")
    fi
fi

# Playwright
if [[ -d "frontend/node_modules/.bin" ]] && [[ -f "frontend/node_modules/.bin/playwright" || -f "frontend/node_modules/.bin/playwright.cmd" ]]; then
    echo "  ✓ Playwright installed in frontend"
    INSTALLED+=("Playwright (e2e testing)")
elif command -v npx &>/dev/null; then
    if npx playwright --version &>/dev/null 2>&1; then
        echo "  ✓ Playwright available via npx"
        INSTALLED+=("Playwright (e2e testing)")
    else
        echo "  Installing Playwright..."
        if [[ -d "frontend" ]]; then
            (cd frontend && npm install -D @playwright/test 2>&1 | tail -3 && npx playwright install chromium 2>&1 | tail -3)
            INSTALLED+=("Playwright (e2e testing)")
        else
            WARNINGS+=("No frontend/ directory — skipped Playwright install")
        fi
    fi
else
    WARNINGS+=("npx not available — cannot install Playwright")
fi

# Supabase CLI
if command -v supabase &>/dev/null; then
    echo "  ✓ Supabase CLI $(supabase --version 2>/dev/null | head -1 || echo 'installed')"
    INSTALLED+=("Supabase CLI")
else
    echo "  Installing Supabase CLI..."
    if sys_install "supabase" "supabase/tap/supabase"; then
        INSTALLED+=("Supabase CLI")
    else
        WARNINGS+=("Cannot auto-install Supabase CLI. Install manually: https://supabase.com/docs/guides/cli/getting-started")
    fi
fi

# Claude CLI
if command -v claude &>/dev/null; then
    echo "  ✓ Claude Code CLI installed"
    INSTALLED+=("Claude Code CLI")
else
    echo "  Installing Claude Code CLI..."
    if command -v npm &>/dev/null; then
        npm install -g @anthropic-ai/claude-code 2>&1 | tail -3
        INSTALLED+=("Claude Code CLI")
    else
        WARNINGS+=("npm not found — cannot install Claude Code CLI. Install manually: npm install -g @anthropic-ai/claude-code")
    fi
fi

echo ""

# ============================================================
# Summary
# ============================================================

echo "═══════════════════════════════════════════════════════════"
echo " SETUP COMPLETE"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [[ ${#INSTALLED[@]} -gt 0 ]]; then
    echo "Installed/Verified:"
    for item in "${INSTALLED[@]}"; do
        echo "  ✓ $item"
    done
    echo ""
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "Warnings:"
    for item in "${WARNINGS[@]}"; do
        echo "  ⚠ $item"
    done
    echo ""
fi

echo "Next steps:"
echo "  1. Edit CLAUDE.md to fill in your project name and description"
echo "  2. Start building: just describe what you want to Claude Code!"
echo ""
