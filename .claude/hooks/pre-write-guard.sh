#!/usr/bin/env bash
# Pre-write guard: blocks writes to sensitive files and detects hardcoded secrets
# Triggered on: PreToolUse Write|Edit
# Exit 0 = allow, Exit 2 = block

# Safety: any unexpected error allows the command through (must be first)
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/mode.sh"

AUDIT_LOG=".claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true

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
    '(^|/)\.env$'
    '(^|/)\.env\.'
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
        friendly_block_with_action \
            "This file contains sensitive information (passwords, API keys, certificates)." \
            "I'll store secrets as environment variables instead."
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
        friendly_block_with_action \
            "This includes a master database key that would be visible to anyone using your app." \
            "I'll switch to the safe public key for frontend code."
    fi
fi

# --- BLOCK: Hardcoded secrets in content ---
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
    # Database connection strings with credentials embedded
    'postgresql://[^:]+:[^@]{8,}@'
    'mysql://[^:]+:[^@]{8,}@'
    'mongodb(\+srv)?://[^:]+:[^@]{8,}@'
)

# Detect secret type for better messaging
detect_secret_type() {
    local content="$1"
    if echo "$content" | grep -qE 'AKIA[0-9A-Z]{16}'; then echo "AWS access key"; return; fi
    if echo "$content" | grep -qE 'sk-ant-'; then echo "Anthropic API key"; return; fi
    if echo "$content" | grep -qE 'sk-[a-zA-Z0-9]{20,}'; then echo "API key"; return; fi
    if echo "$content" | grep -qE 'ghp_|gho_'; then echo "GitHub token"; return; fi
    if echo "$content" | grep -qE 'eyJ.*\.eyJ'; then echo "JWT token"; return; fi
    if echo "$content" | grep -qiE 'password\s*='; then echo "password"; return; fi
    echo "secret"
}

for pattern in "${SECRET_PATTERNS[@]}"; do
    if echo "$CONTENT_CHECK" | grep -qE "$pattern"; then
        SECRET_TYPE=$(detect_secret_type "$CONTENT_CHECK")
        echo "[$TIMESTAMP] BLOCKED: Hardcoded secret detected in: $FILE_PATH (pattern: $pattern)" >> "$AUDIT_LOG"
        friendly_block_with_action \
            "I found a $SECRET_TYPE written directly in the code." \
            "I'll move this to an environment variable."
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
        friendly_block_with_action \
            "This database query is built by joining text together, which could let attackers manipulate your data." \
            "I'll rewrite this using the query builder."
    fi
done

# --- BLOCK: eval() in JS/TS files ---
if echo "$FILE_PATH" | grep -qiE '\.(js|jsx|ts|tsx|vue)$'; then
    if echo "$CONTENT_CHECK" | grep -qE '\beval\s*\('; then
        echo "[$TIMESTAMP] BLOCKED: eval() usage in: $FILE_PATH" >> "$AUDIT_LOG"
        friendly_block_with_action \
            "This code runs text as a program, which is a security risk." \
            "I'll replace this with a safer approach."
    fi
fi

# --- WARN: TODO/FIXME count ---
TODO_COUNT=$(echo "$CONTENT_CHECK" | grep -ciE '\bTODO\b|\bFIXME\b' 2>/dev/null; true)
if [[ "$TODO_COUNT" -gt 2 ]]; then
    echo "[$TIMESTAMP] WARNING: $TODO_COUNT TODO/FIXME markers in: $FILE_PATH" >> "$AUDIT_LOG"
fi

exit 0
