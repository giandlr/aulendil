#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────
# Managers' Agent Fleet Installer
#
# Usage:
#   1. Copy managers-agent-fleet.zip into your project root
#   2. unzip managers-agent-fleet.zip
#   3. bash managers-agent-fleet/install.sh
#
# The installer copies files from the managers-agent-fleet/
# folder into your project, then cleans up after itself.
# ─────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Safety check: make sure we're inside a managers-agent-fleet/ subfolder
if [ "$(basename "$SCRIPT_DIR")" != "managers-agent-fleet" ]; then
  echo ""
  echo "  Error: install.sh must be inside a managers-agent-fleet/ folder."
  echo "  Expected: unzip managers-agent-fleet.zip → then run bash managers-agent-fleet/install.sh"
  echo ""
  exit 1
fi

echo ""
echo "  Installing Managers' Agent Fleet into: $PROJECT_DIR"
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

# sprout-bootstrap.sh + sprout-init.sh (legacy)
mkdir -p "$PROJECT_DIR/scripts"
cp "$SCRIPT_DIR/scripts/sprout-bootstrap.sh" "$PROJECT_DIR/scripts/sprout-bootstrap.sh"
cp "$SCRIPT_DIR/scripts/sprout-init.sh" "$PROJECT_DIR/scripts/sprout-init.sh"

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
    chmod +x "$PROJECT_DIR/scripts/sprout-bootstrap.sh"
    chmod +x "$PROJECT_DIR/scripts/sprout-init.sh"
    ;;
esac

# ── 3. Add .gitignore entries ────────────────────────

GITIGNORE="$PROJECT_DIR/.gitignore"
MARKER="# ── Managers' Agent Fleet (do not commit) ──"

if [ -f "$GITIGNORE" ] && grep -qF "$MARKER" "$GITIGNORE"; then
  echo "  .gitignore already has toolkit entries — skipped."
else
  cat >> "$GITIGNORE" <<'GITIGNORE_BLOCK'

# ── Managers' Agent Fleet (do not commit) ──
# Internal AI config — never commit
.claude/
CLAUDE.md
CLAUDE.md.template
CLAUDE.local.md
# Runtime mode and gate config — environment-specific
.claude/mode
.claude/deploy-gates.json
# Docs are reference material, not project deliverables
docs/architecture.md
docs/api-conventions.md
docs/done-checklist.md
docs/tech-stack.md
docs/changelog-guide.md
docs/enterprise-features.md
scripts/sprout-init.sh
scripts/sprout-bootstrap.sh
# Installer artefacts
managers-agent-fleet/
managers-agent-fleet.zip
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
  if [ -f "$GLOBAL_SETTINGS" ] && command -v python3 &>/dev/null; then
    python3 - "$GLOBAL_SETTINGS" <<'PYTHON_EOF'
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
rm -f "$PROJECT_DIR/managers-agent-fleet.zip"

# ── 7. Done ──────────────────────────────────────────

echo ""
echo "  Done! Next steps:"
echo ""
echo "    1. Edit CLAUDE.md — replace [APP_NAME] with your app's name"
echo "    2. Run: bash scripts/sprout-bootstrap.sh    (scaffolds app + starts everything)"
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
