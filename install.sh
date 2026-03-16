#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────
# Aulendil Installer
#
# Usage:
#   1. Copy aulendil.zip into your project root
#   2. unzip aulendil.zip
#   3. bash aulendil/install.sh
#
# The installer copies files from the aulendil/
# folder into your project, then cleans up after itself.
# ─────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Safety check: make sure we're inside a aulendil/ subfolder
if [ "$(basename "$SCRIPT_DIR")" != "aulendil" ]; then
  echo ""
  echo "  Error: install.sh must be inside a aulendil/ folder."
  echo "  Expected: unzip aulendil.zip → then run bash aulendil/install.sh"
  echo ""
  exit 1
fi

echo ""
echo "  Installing Aulendil into: $PROJECT_DIR"
echo ""

# ── 1. Copy toolkit files ────────────────────────────

# .claude directory (agents, hooks, rules, reviewers, scripts, settings)
mkdir -p "$PROJECT_DIR/.claude"
for subdir in agents hooks rules reviewers scripts; do
  if [ -d "$SCRIPT_DIR/.claude/$subdir" ]; then
    mkdir -p "$PROJECT_DIR/.claude/$subdir"
    cp -R "$SCRIPT_DIR/.claude/$subdir/"* "$PROJECT_DIR/.claude/$subdir/"
  fi
done

# settings.json
cp "$SCRIPT_DIR/.claude/settings.json" "$PROJECT_DIR/.claude/settings.json"

# CLAUDE.md (project root — only if not already present)
if [ ! -f "$PROJECT_DIR/CLAUDE.md" ]; then
  cp "$SCRIPT_DIR/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md"
  echo "  Created CLAUDE.md — edit [APP_NAME] with your app's name."
else
  echo "  CLAUDE.md already exists — skipped. Template saved as CLAUDE.md.template"
  cp "$SCRIPT_DIR/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md.template"
fi

# CHANGELOG.md (only if not already present)
if [ ! -f "$PROJECT_DIR/CHANGELOG.md" ]; then
  cp "$SCRIPT_DIR/CHANGELOG.md" "$PROJECT_DIR/CHANGELOG.md"
fi

# docs/
mkdir -p "$PROJECT_DIR/docs"
for doc in "$SCRIPT_DIR"/docs/*.md; do
  [ -f "$doc" ] || continue
  cp "$doc" "$PROJECT_DIR/docs/$(basename "$doc")"
done

# bootstrap.sh + init.sh (legacy)
mkdir -p "$PROJECT_DIR/scripts"
cp "$SCRIPT_DIR/scripts/bootstrap.sh" "$PROJECT_DIR/scripts/bootstrap.sh"
cp "$SCRIPT_DIR/scripts/init.sh" "$PROJECT_DIR/scripts/init.sh"

# Cloud deployment scripts
for script in deploy-cloud.sh scaffold-cloud-configs.sh generate-handoff-doc.sh setup-supabase-cloud.sh; do
    if [ -f "$SCRIPT_DIR/.claude/scripts/$script" ]; then
        cp "$SCRIPT_DIR/.claude/scripts/$script" "$PROJECT_DIR/.claude/scripts/$script"
    fi
done

# ── 1b. Mode system and deploy gates ─────────────────

# .claude/mode (default: build)
echo "build" > "$PROJECT_DIR/.claude/mode"
echo "  Created .claude/mode (default: build)"

# .claude/hooks/lib/ directory
mkdir -p "$PROJECT_DIR/.claude/hooks/lib"

# .claude/deploy-gates.json
if [ -f "$SCRIPT_DIR/.claude/deploy-gates.json" ]; then
  cp "$SCRIPT_DIR/.claude/deploy-gates.json" "$PROJECT_DIR/.claude/deploy-gates.json"
  echo "  Created .claude/deploy-gates.json"
fi

# ── 2. Make scripts executable (skip on Windows) ────

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "  Skipping chmod (not needed on Windows)."
    ;;
  *)
    find "$PROJECT_DIR/.claude/hooks" -name "*.sh" -exec chmod +x {} \;
    find "$PROJECT_DIR/.claude/scripts" -name "*.sh" -exec chmod +x {} \;
    chmod +x "$PROJECT_DIR/scripts/bootstrap.sh"
    chmod +x "$PROJECT_DIR/scripts/init.sh"
    ;;
esac

# ── 3. Add .gitignore entries ────────────────────────

GITIGNORE="$PROJECT_DIR/.gitignore"
MARKER="# ── Aulendil (do not commit) ──"

if [ -f "$GITIGNORE" ] && grep -qF "$MARKER" "$GITIGNORE"; then
  echo "  .gitignore already has toolkit entries — skipped."
else
  cat >> "$GITIGNORE" <<'GITIGNORE_BLOCK'

# ── Aulendil (do not commit) ──
# AI toolkit config — hooks, rules, agents, scripts, session state
.claude/
# Project instructions (toolkit-managed, not project source)
CLAUDE.md
CLAUDE.md.template
CLAUDE.local.md
# Reference docs (toolkit material, not project deliverables)
docs/architecture.md
docs/api-conventions.md
docs/done-checklist.md
docs/tech-stack.md
docs/changelog-guide.md
docs/enterprise-features.md
# Toolkit scripts
scripts/init.sh
scripts/bootstrap.sh
# Installer artefacts
aulendil/
aulendil.zip
GITIGNORE_BLOCK
  echo "  Updated .gitignore — toolkit files will not be committed."
fi

# ── 4. Create tmp directory ──────────────────────────

mkdir -p "$PROJECT_DIR/.claude/tmp"

# ── 5. Configure global Claude Code permissions ──────
#
# Sub-agents spawned via the Task tool use the user-level
# ~/.claude/settings.json, not the project-level one.
# We patch it once so all sessions (including sub-agents)
# never prompt for permission.

GLOBAL_SETTINGS="$HOME/.claude/settings.json"
PERMISSIONS_MARKER='"Bash(*)"'

if [ -f "$GLOBAL_SETTINGS" ] && grep -qF "$PERMISSIONS_MARKER" "$GLOBAL_SETTINGS"; then
  echo "  Global permissions already configured — skipped."
else
  if [ -f "$GLOBAL_SETTINGS" ] && { PYTHON_CMD=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || command -v py 2>/dev/null); [ -n "$PYTHON_CMD" ]; }; then
    "$PYTHON_CMD" - "$GLOBAL_SETTINGS" <<'PYTHON_EOF'
import json, sys

path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

cfg.setdefault("permissions", {})
cfg["permissions"]["allow"] = [
    "Bash(*)", "Read(*)", "Write(*)", "Edit(*)",
    "Glob(*)", "Grep(*)", "Task(*)", "WebFetch(*)", "WebSearch(*)"
]
cfg["permissions"].setdefault("deny", [])

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print("  Global ~/.claude/settings.json updated with auto-approve permissions.")
PYTHON_EOF
  else
    # No existing settings or no python3 — write a minimal file
    mkdir -p "$HOME/.claude"
    cat > "$GLOBAL_SETTINGS" <<'SETTINGS_EOF'
{
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Write(*)", "Edit(*)", "Glob(*)", "Grep(*)", "Task(*)", "WebFetch(*)", "WebSearch(*)"],
    "deny": []
  }
}
SETTINGS_EOF
    echo "  Created ~/.claude/settings.json with auto-approve permissions."
  fi
fi

# ── 6. Clean up ──────────────────────────────────────

echo "  Cleaning up installer files..."
rm -rf "$SCRIPT_DIR"
rm -f "$PROJECT_DIR/aulendil.zip"

# ── 7. Done ──────────────────────────────────────────

echo ""
echo "  Done! Next steps:"
echo ""
echo "    1. Edit CLAUDE.md — replace [APP_NAME] with your app's name"
echo "    2. Run: bash scripts/bootstrap.sh    (scaffolds app + starts everything)"
echo "    3. Open Claude Code and start describing what you want to build"
echo ""
echo "  How the mode system works:"
echo ""
echo "    BUILD mode (default) — You build freely. Only security issues are blocked."
echo "    Claude auto-fixes quality issues and explains what it did in plain English."
echo ""
echo "    DEPLOY mode — When you say 'ship it' or 'share with my team,' Claude asks"
echo "    which level of validation to run:"
echo "      - MVP:        Quick check — just for you to test"
echo "      - Team:       Tests + basic quality — sharing with colleagues"
echo "      - Production: Full pipeline — external users or company-wide"
echo ""
