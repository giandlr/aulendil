#!/usr/bin/env bash
# Detects git tag commands in Bash tool output and triggers tag-release.sh
# Triggered on: PostToolUse Bash

# Safety: any unexpected error allows the command through
trap 'exit 0' ERR

INPUT=$(cat)

# Extract the command from the JSON input (macOS-safe: no \s in sed)
CMD=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")

# Fallback: try jq if available
if [[ -z "$CMD" ]] && command -v jq &>/dev/null; then
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || echo "")
fi

# Check if it's a git tag command with a version number
if echo "$CMD" | grep -qE 'git\s+tag\s+(-a\s+)?v[0-9]'; then
    VERSION=$(echo "$CMD" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9.-]*' | head -1)
    if [[ -n "$VERSION" && -f ".claude/scripts/tag-release.sh" ]]; then
        bash .claude/scripts/tag-release.sh "$VERSION"
    fi
fi

exit 0
