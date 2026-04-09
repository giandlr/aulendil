#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────
# Aulendil Framework Updater
#
# Updates the framework infrastructure in an existing project.
# Safe to run at any time — only touches framework-owned files.
# Never overwrites: CLAUDE.md, .env, .claude/mode, .claude/brief.md,
#                   .claude/session/, .claude/tmp/
#
# Usage (from your project root):
#   unzip aulendil.zip
#   bash aulendil/update.sh
# ─────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Safety check: must be inside a aulendil/ subfolder
if [ "$(basename "$SCRIPT_DIR")" != "aulendil" ]; then
  echo ""
  echo "  Error: update.sh must be run from inside the aulendil/ folder."
  echo "  Expected: unzip aulendil.zip → then run bash aulendil/update.sh"
  echo ""
  exit 1
fi

# Safety check: target must look like an aulendil project
if [ ! -d "$PROJECT_DIR/.claude" ]; then
  echo ""
  echo "  Error: no .claude/ directory found in $PROJECT_DIR"
  echo "  This doesn't look like an aulendil project."
  echo "  Run bash aulendil/install.sh for a fresh install."
  echo ""
  exit 1
fi

# Read versions
NEW_VERSION="$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")"
OLD_VERSION="$(cat "$PROJECT_DIR/.claude/version" 2>/dev/null | tr -d '[:space:]' || echo "unknown")"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Aulendil Framework Updater"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Project: $PROJECT_DIR"
echo "  Current version: $OLD_VERSION"
echo "  New version:     $NEW_VERSION"
echo ""

if [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
  echo "  Already on v$NEW_VERSION — nothing to update."
  echo ""
  rm -rf "$SCRIPT_DIR"
  exit 0
fi

echo "  Updating framework files..."
echo "  (Your app code, CLAUDE.md, and .env are not touched.)"
echo ""

# ── Framework infrastructure files ───────────────────
# These are owned by aulendil — always overwritten.

# .claude/scripts/
mkdir -p "$PROJECT_DIR/.claude/scripts"
if ls "$SCRIPT_DIR/.claude/scripts/"*.sh &>/dev/null 2>&1; then
  cp "$SCRIPT_DIR/.claude/scripts/"*.sh "$PROJECT_DIR/.claude/scripts/"
  echo "  + .claude/scripts/ ($(ls "$SCRIPT_DIR/.claude/scripts/"*.sh | wc -l | tr -d ' ') scripts)"
fi

# .claude/hooks/
mkdir -p "$PROJECT_DIR/.claude/hooks"
if ls "$SCRIPT_DIR/.claude/hooks/"*.sh &>/dev/null 2>&1; then
  cp "$SCRIPT_DIR/.claude/hooks/"*.sh "$PROJECT_DIR/.claude/hooks/"
  echo "  + .claude/hooks/"
fi
mkdir -p "$PROJECT_DIR/.claude/hooks/lib"
if ls "$SCRIPT_DIR/.claude/hooks/lib/"* &>/dev/null 2>&1; then
  cp "$SCRIPT_DIR/.claude/hooks/lib/"* "$PROJECT_DIR/.claude/hooks/lib/"
fi

# .claude/rules/
mkdir -p "$PROJECT_DIR/.claude/rules"
if ls "$SCRIPT_DIR/.claude/rules/"*.md &>/dev/null 2>&1; then
  cp "$SCRIPT_DIR/.claude/rules/"*.md "$PROJECT_DIR/.claude/rules/"
  echo "  + .claude/rules/"
fi

# .claude/agents/
mkdir -p "$PROJECT_DIR/.claude/agents"
if ls "$SCRIPT_DIR/.claude/agents/"*.md &>/dev/null 2>&1; then
  cp "$SCRIPT_DIR/.claude/agents/"*.md "$PROJECT_DIR/.claude/agents/"
  echo "  + .claude/agents/"
fi

# .claude/reviewers/
mkdir -p "$PROJECT_DIR/.claude/reviewers"
if ls "$SCRIPT_DIR/.claude/reviewers/"*.md &>/dev/null 2>&1; then
  cp "$SCRIPT_DIR/.claude/reviewers/"*.md "$PROJECT_DIR/.claude/reviewers/"
  echo "  + .claude/reviewers/"
fi

# .claude/refs/ (on-demand reference docs — not auto-loaded into context)
mkdir -p "$PROJECT_DIR/.claude/refs"
if ls "$SCRIPT_DIR/.claude/refs/"*.md &>/dev/null 2>&1; then
  cp "$SCRIPT_DIR/.claude/refs/"*.md "$PROJECT_DIR/.claude/refs/"
  echo "  + .claude/refs/"
fi

# .claude/deploy-gates.json and settings.json
cp "$SCRIPT_DIR/.claude/deploy-gates.json" "$PROJECT_DIR/.claude/deploy-gates.json"
cp "$SCRIPT_DIR/.claude/settings.json" "$PROJECT_DIR/.claude/settings.json"
echo "  + .claude/deploy-gates.json"
echo "  + .claude/settings.json"

# scripts/ (bootstrap, stop, init, refresh-deps)
mkdir -p "$PROJECT_DIR/scripts"
cp "$SCRIPT_DIR/scripts/bootstrap.sh"    "$PROJECT_DIR/scripts/bootstrap.sh"
cp "$SCRIPT_DIR/scripts/stop.sh"         "$PROJECT_DIR/scripts/stop.sh"
cp "$SCRIPT_DIR/scripts/init.sh"         "$PROJECT_DIR/scripts/init.sh"
cp "$SCRIPT_DIR/scripts/refresh-deps.sh" "$PROJECT_DIR/scripts/refresh-deps.sh" 2>/dev/null || true
echo "  + scripts/bootstrap.sh, stop.sh, init.sh, refresh-deps.sh"

# docs/ (framework reference docs + CHANGELOG)
mkdir -p "$PROJECT_DIR/docs"
for doc in "$SCRIPT_DIR"/docs/*.md; do
  [ -f "$doc" ] || continue
  cp "$doc" "$PROJECT_DIR/docs/$(basename "$doc")"
done
[ -f "$SCRIPT_DIR/CHANGELOG.md" ] && cp "$SCRIPT_DIR/CHANGELOG.md" "$PROJECT_DIR/docs/CHANGELOG.md"
echo "  + docs/"

# manual/
if [ -f "$SCRIPT_DIR/manual/guide.html" ]; then
  mkdir -p "$PROJECT_DIR/manual"
  cp "$SCRIPT_DIR/manual/guide.html" "$PROJECT_DIR/manual/guide.html"
  echo "  + manual/guide.html"
fi

# ── Files explicitly NOT updated ─────────────────────
# CLAUDE.md          — customized with app name and description
# .env               — contains real secrets
# .claude/mode       — reflects current build/deploy state
# .claude/brief.md   — app planning artifact
# .claude/session/   — conversation checkpoints
# .claude/tmp/       — pipeline run artifacts

# ── Permissions ──────────────────────────────────────

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    ;;
  *)
    find "$PROJECT_DIR/.claude/hooks"   -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find "$PROJECT_DIR/.claude/scripts" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    chmod +x "$PROJECT_DIR/scripts/bootstrap.sh"    2>/dev/null || true
    chmod +x "$PROJECT_DIR/scripts/stop.sh"        2>/dev/null || true
    chmod +x "$PROJECT_DIR/scripts/init.sh"        2>/dev/null || true
    chmod +x "$PROJECT_DIR/scripts/refresh-deps.sh" 2>/dev/null || true
    ;;
esac

# ── Save new version ──────────────────────────────────

echo "$NEW_VERSION" > "$PROJECT_DIR/.claude/version"

# ── Clean up ──────────────────────────────────────────

rm -rf "$SCRIPT_DIR"
rm -f "$(dirname "$SCRIPT_DIR")/aulendil.zip" 2>/dev/null || true

# ── Done ─────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Updated: v$OLD_VERSION → v$NEW_VERSION"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Your app code and configuration were not changed."
echo "  No need to re-run bootstrap."
echo ""
echo "  To update dependencies to latest stable versions:"
echo "    bash scripts/refresh-deps.sh"
echo ""
echo "  What's new: see CHANGELOG.md in your project docs/"
echo ""
