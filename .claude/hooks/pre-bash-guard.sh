#!/usr/bin/env bash
# Pre-bash guard: blocks destructive shell commands
# Triggered on: PreToolUse Bash
# Exit 0 = allow, Exit 2 = block

# Safety: any unexpected error allows the command through (must be first)
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/mode.sh"

AUDIT_LOG=".claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true

# Read tool input from stdin
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | grep -oE '"command"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")

# Fallback: try jq if available
if [[ -z "$COMMAND" ]] && command -v jq &>/dev/null; then
    COMMAND=$(echo "$INPUT" | jq -r '.command // empty' 2>/dev/null || echo "")
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] PRE-BASH: $COMMAND" >> "$AUDIT_LOG"

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# --- BLOCK: Catastrophic file deletion ---
if echo "$COMMAND" | grep -qE 'rm\s+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*\s+/\s*$|rm\s+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*\s+~'; then
    echo "[$TIMESTAMP] BLOCKED: Destructive rm command: $COMMAND" >> "$AUDIT_LOG"
    friendly_block_with_action \
        "This command would permanently delete critical system files." \
        "I can target specific files instead."
fi

if echo "$COMMAND" | grep -qE 'rm\s+-rf\s+/\s*$|rm\s+-rf\s+/$|rm\s+-rf\s+~'; then
    echo "[$TIMESTAMP] BLOCKED: Destructive rm command: $COMMAND" >> "$AUDIT_LOG"
    friendly_block_with_action \
        "This command would permanently delete critical system files." \
        "I can target specific files instead."
fi

# --- BLOCK: Destructive database commands ---
DB_DESTRUCTIVE_PATTERNS=(
    '\bDROP\s+TABLE\b'
    '\bDROP\s+DATABASE\b'
    '\bTRUNCATE\b'
    '\bDELETE\s+FROM\s+\S+\s+WHERE\s+1\b'
    '\bDELETE\s+FROM\s+\S+\s*;'
)

for pattern in "${DB_DESTRUCTIVE_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qiE "$pattern"; then
        echo "[$TIMESTAMP] BLOCKED: Destructive DB command: $COMMAND" >> "$AUDIT_LOG"
        friendly_block_with_action \
            "This command would permanently destroy database data." \
            "I'll use soft deletes or a safe migration."
    fi
done

# --- BLOCK: supabase db reset (wipes all data) ---
if echo "$COMMAND" | grep -qE 'supabase\s+db\s+reset'; then
    echo "[$TIMESTAMP] BLOCKED: supabase db reset: $COMMAND" >> "$AUDIT_LOG"
    friendly_block_with_action \
        "This would wipe all database data and re-seed from scratch." \
        "I'll apply the migration forward with 'supabase db push' instead."
fi

# --- BLOCK: Force push to main/master ---
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force.*\s+(main|master)|git\s+push\s+-f.*\s+(main|master)'; then
    echo "[$TIMESTAMP] BLOCKED: Force push to protected branch: $COMMAND" >> "$AUDIT_LOG"
    friendly_block_with_action \
        "Force push to the main branch could overwrite your team's work." \
        "I'll use a feature branch and pull request."
fi

# --- BLOCK: Dangerous permissions ---
if echo "$COMMAND" | grep -qE 'chmod\s+-R\s+777'; then
    echo "[$TIMESTAMP] BLOCKED: chmod -R 777: $COMMAND" >> "$AUDIT_LOG"
    friendly_block_with_action \
        "This would make all files readable and writable by anyone." \
        "I'll set more restrictive permissions (755/644)."
fi

# --- BLOCK: dd commands (disk destruction risk) ---
if echo "$COMMAND" | grep -qE '\bdd\s+if='; then
    echo "[$TIMESTAMP] BLOCKED: dd command: $COMMAND" >> "$AUDIT_LOG"
    friendly_block_with_action \
        "This low-level disk command could destroy data." \
        "This needs manual execution with explicit parameters."
fi

# --- WARN: Package install without lockfile save ---
if echo "$COMMAND" | grep -qE 'npm\s+install\s' && ! echo "$COMMAND" | grep -qE '\s--save|\s--save-dev|\s-D|\s-S'; then
    if echo "$COMMAND" | grep -qE 'npm\s+install\s+\S'; then
        echo "[$TIMESTAMP] WARNING: npm install without --save flag: $COMMAND" >> "$AUDIT_LOG"
    fi
fi

if echo "$COMMAND" | grep -qE 'pip\s+install\s' && ! echo "$COMMAND" | grep -qE 'requirements\.txt|pyproject\.toml|-r\s'; then
    echo "[$TIMESTAMP] WARNING: pip install without requirements file: $COMMAND" >> "$AUDIT_LOG"
fi

# --- WARN: Pipe to shell (curl | bash) ---
if echo "$COMMAND" | grep -qE 'curl\s.*\|\s*(bash|sh|zsh)|wget\s.*\|\s*(bash|sh|zsh)'; then
    echo "[$TIMESTAMP] WARNING: pipe to shell detected: $COMMAND" >> "$AUDIT_LOG"
fi

exit 0
