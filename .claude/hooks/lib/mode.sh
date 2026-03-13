#!/usr/bin/env bash
# Shared mode helper — sourced by all hooks
# Modes: "build" (default) = security-only blocks, "deploy" = full enforcement

get_mode() {
  cat "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")/.claude/mode" 2>/dev/null || echo "build"
}

friendly_block() {
  echo "" >&2
  echo "  $1" >&2
  echo "" >&2
  exit 2
}

log_audit() {
  local AUDIT_LOG="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")/.claude/audit.log"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$AUDIT_LOG"
}
