#!/usr/bin/env bash
# Pre-write guard: blocks writes to sensitive files and detects hardcoded secrets
# Triggered on: PreToolUse Write|Edit
# Exit 0 = allow, Exit 2 = block

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/mode.sh"

AUDIT_LOG=".claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true

# Safety: any unexpected error allows the command through
trap 'exit 0' ERR

# Read tool input from stdin
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")

# Fallback: try jq if available
if [[ -z "$FILE_PATH" ]] && command -v jq &>/dev/null; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // .path // empty' 2>/dev/null || echo "")
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] PRE-WRITE: $FILE_PATH" >> "$AUDIT_LOG"

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# --- BLOCK: Sensitive file paths ---
SENSITIVE_PATTERNS=(
    '\.env'
    '\.pem$'
    '\.key$'
    'id_rsa'
    'credentials'
    '\.secret'
    '\.p12$'
    '\.pfx$'
    '\.jks$'
)

for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    if echo "$FILE_PATH" | grep -qiE "$pattern"; then
        echo "[$TIMESTAMP] BLOCKED: Write to sensitive file: $FILE_PATH" >> "$AUDIT_LOG"
        friendly_block "I can't save this file because it contains sensitive information (passwords, API keys, certificates). These need to go in environment variables to keep your app secure."
    fi
done

# --- BLOCK: BMAD artifacts when fleet mode is active ---
if [[ -f ".claude/fleet-mode" ]]; then
    BMAD_ARTIFACT_PATTERNS=(
        'docs/stories/'
        'docs/prd/'
        'docs/architecture/'
        'docs/ux-design/'
        'docs/epics/'
        '\.story\.md$'
        '\.prd\.md$'
        '\.bmad/'
    )
    for pattern in "${BMAD_ARTIFACT_PATTERNS[@]}"; do
        if echo "$FILE_PATH" | grep -qiE "$pattern"; then
            echo "[$TIMESTAMP] BLOCKED: BMAD artifact write blocked (fleet-mode active): $FILE_PATH" >> "$AUDIT_LOG"
            friendly_block "I can't create planning documents right now because this project is in build mode. To switch back to planning mode, remove the .claude/fleet-mode file."
        fi
    done
fi

# --- BLOCK: SUPABASE_SERVICE_ROLE_KEY in frontend files ---
if echo "$FILE_PATH" | grep -qiE 'frontend/'; then
    CONTENT=$(echo "$INPUT" | grep -oE '"content"\s*:\s*"[^"]*"' | head -1 2>/dev/null || echo "$INPUT")
    if echo "$CONTENT" | grep -qiE 'SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE'; then
        echo "[$TIMESTAMP] BLOCKED: Service role key reference in frontend: $FILE_PATH" >> "$AUDIT_LOG"
        friendly_block "I stopped this because it includes a master database key that would be visible to anyone using your app. I'll use the safe public key instead."
    fi
fi

# --- BLOCK: Hardcoded secrets in content ---
# Extract content for analysis (best effort from the JSON input)
CONTENT_CHECK=$(echo "$INPUT" 2>/dev/null || echo "")

SECRET_PATTERNS=(
    'password\s*=\s*["\x27][^"\x27]+'
    'secret\s*=\s*["\x27][^"\x27]+'
    'api_key\s*=\s*["\x27][^"\x27]+'
    'apikey\s*=\s*["\x27][^"\x27]+'
    'AKIA[0-9A-Z]{16}'
    'sk-[a-zA-Z0-9]{20,}'
    'sk-ant-[a-zA-Z0-9-]{20,}'
    'eyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.[a-zA-Z0-9_-]*'
    'ghp_[a-zA-Z0-9]{36}'
    'gho_[a-zA-Z0-9]{36}'
)

for pattern in "${SECRET_PATTERNS[@]}"; do
    if echo "$CONTENT_CHECK" | grep -qE "$pattern"; then
        echo "[$TIMESTAMP] BLOCKED: Hardcoded secret detected in: $FILE_PATH (pattern: $pattern)" >> "$AUDIT_LOG"
        friendly_block "I found a password or API key written directly in the code. These need to be stored as environment variables so they stay private."
    fi
done

# --- BLOCK: SQL injection risk (string concatenation in SQL) ---
SQL_INJECTION_PATTERNS=(
    'f"[^"]*\b(SELECT|INSERT|UPDATE|DELETE|DROP|ALTER)\b'
    "f'[^']*\b(SELECT|INSERT|UPDATE|DELETE|DROP|ALTER)\b"
    '"\s*\+\s*.*\b(SELECT|INSERT|UPDATE|DELETE|DROP|ALTER)\b'
    '\bexec\s*\(\s*f["\x27]'
    '\bcursor\.execute\s*\(\s*f["\x27]'
)

for pattern in "${SQL_INJECTION_PATTERNS[@]}"; do
    if echo "$CONTENT_CHECK" | grep -qiE "$pattern"; then
        echo "[$TIMESTAMP] BLOCKED: SQL injection risk in: $FILE_PATH" >> "$AUDIT_LOG"
        friendly_block "I found a database query built by joining text together, which could let attackers manipulate your data. I'll use the safe query builder instead."
    fi
done

# --- BLOCK: eval() in JS/TS files ---
if echo "$FILE_PATH" | grep -qiE '\.(js|jsx|ts|tsx|vue)$'; then
    if echo "$CONTENT_CHECK" | grep -qE '\beval\s*\('; then
        echo "[$TIMESTAMP] BLOCKED: eval() usage in: $FILE_PATH" >> "$AUDIT_LOG"
        friendly_block "I found code that runs text as a program, which is a security risk. I'll use a safer approach."
    fi
fi

# --- WARN: TODO/FIXME count ---
TODO_COUNT=$(echo "$CONTENT_CHECK" | grep -ciE '\bTODO\b|\bFIXME\b' 2>/dev/null; true)
if [[ "$TODO_COUNT" -gt 2 ]]; then
    echo "[$TIMESTAMP] WARNING: $TODO_COUNT TODO/FIXME markers in: $FILE_PATH" >> "$AUDIT_LOG"
fi

exit 0
