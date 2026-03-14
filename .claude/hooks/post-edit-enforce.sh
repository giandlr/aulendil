#!/usr/bin/env bash
# Post-edit enforcement: mode-aware checks after every file write/edit
# BUILD mode: security-only blocks + warnings logged
# DEPLOY mode: full pipeline enforcement
# Triggered on: PostToolUse Write|Edit
# Exit 0 = pass/warn, Exit 2 = block (Claude must fix)

# Safety: unexpected errors allow the command through (intentional exit 2 still blocks)
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/mode.sh"

AUDIT_LOG=".claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true

# Read tool input from stdin
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")

if [[ -z "$FILE_PATH" ]] && command -v jq &>/dev/null; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // .path // empty' 2>/dev/null || echo "")
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] POST-EDIT: $FILE_PATH" >> "$AUDIT_LOG"

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# --- Session file log (append modified file for crash recovery) ---
SESSION_DIR=".claude/session"
mkdir -p "$SESSION_DIR" 2>/dev/null || true
echo "$FILE_PATH" >> "$SESSION_DIR/file-log.txt"

MODE=$(get_mode)
BLOCKED=false
BLOCK_MESSAGES=()

# Helper: count lines in file
file_line_count() {
    wc -l < "$1" 2>/dev/null | tr -d ' '
}

# ============================================================
# SECURITY CHECKS — always run in both BUILD and DEPLOY modes
# ============================================================

# Gitleaks secret scan
if command -v gitleaks &>/dev/null; then
    GITLEAKS_OUTPUT=$(gitleaks detect --source="$FILE_PATH" --no-git 2>&1) || {
        GITLEAKS_EXIT=$?
        if [[ $GITLEAKS_EXIT -ne 0 ]]; then
            BLOCKED=true
            BLOCK_MESSAGES+=("I found a secret (password, API key, or token) in this file. Secrets must be stored as environment variables, never written into code.")
            echo "[$TIMESTAMP] BLOCKED: gitleaks found secrets in $FILE_PATH" >> "$AUDIT_LOG"
        fi
    }
fi

# SUPABASE_SERVICE_ROLE_KEY in frontend files
if echo "$FILE_PATH" | grep -qiE 'frontend/'; then
    FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")
    if echo "$FILE_CONTENT" | grep -qiE 'SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_KEY'; then
        BLOCKED=true
        BLOCK_MESSAGES+=("This includes a master database key visible to app users. I'll switch to the safe public key.")
        echo "[$TIMESTAMP] BLOCKED: Service role key in frontend file $FILE_PATH" >> "$AUDIT_LOG"
    fi
fi

# Direct Supabase client calls outside services/
if echo "$FILE_PATH" | grep -qiE 'frontend/.*\.(ts|tsx|js|jsx|vue)$'; then
    if ! echo "$FILE_PATH" | grep -qE 'services/'; then
        FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")
        if echo "$FILE_CONTENT" | grep -qE 'supabase\.(from|rpc|auth|storage|channel|removeChannel)\s*\('; then
            BLOCKED=true
            BLOCK_MESSAGES+=("This file calls the Supabase client directly. All data access must go through frontend/services/.")
            echo "[$TIMESTAMP] BLOCKED: Direct Supabase call in $FILE_PATH" >> "$AUDIT_LOG"
        fi
    fi
fi

# ============================================================
# BUILD MODE: log warnings + new detections (warn only)
# ============================================================
if [[ "$MODE" == "build" ]]; then

    if echo "$FILE_PATH" | grep -qE '\.(ts|tsx|js|jsx|vue)$'; then
        # Console.log
        if grep -qE '\bconsole\.(log|debug)\b' "$FILE_PATH" 2>/dev/null; then
            echo "[$TIMESTAMP] AUDIT (build): console.log found in $FILE_PATH" >> "$AUDIT_LOG"
        fi

        # Oversized components
        if echo "$FILE_PATH" | grep -qE '\.vue$'; then
            LINE_COUNT=$(file_line_count "$FILE_PATH")
            if [[ "$LINE_COUNT" -gt 200 ]]; then
                echo "[$TIMESTAMP] AUDIT (build): Oversized component $FILE_PATH ($LINE_COUNT lines)" >> "$AUDIT_LOG"
            fi

            FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")

            # Missing loading state
            if echo "$FILE_CONTENT" | grep -qE 'await\s|\.then\s*\(|useFetch|useAsyncData|useLazyFetch'; then
                if ! echo "$FILE_CONTENT" | grep -qiE 'loading|isLoading|pending|isFetching|skeleton|spinner'; then
                    echo "[$TIMESTAMP] AUDIT (build): Missing loading state in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi

            # Missing error state
            if echo "$FILE_CONTENT" | grep -qE 'await\s|\.then\s*\(|useFetch|useAsyncData|useLazyFetch'; then
                if ! echo "$FILE_CONTENT" | grep -qiE 'error|isError|catch\s*\(|\.catch|onError|ErrorAlert|error-alert'; then
                    echo "[$TIMESTAMP] AUDIT (build): Missing error state in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi

            # Missing empty state
            if echo "$FILE_CONTENT" | grep -qE 'v-for\s*='; then
                if ! echo "$FILE_CONTENT" | grep -qiE '\.length\s*===?\s*0|empty|no-data|no-results|EmptyState|empty-state'; then
                    echo "[$TIMESTAMP] AUDIT (build): Missing empty state for list in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi
        fi
    fi

    if echo "$FILE_PATH" | grep -qE '\.py$'; then
        # Bare except clauses
        if grep -qE '^\s*except\s*:' "$FILE_PATH" 2>/dev/null; then
            echo "[$TIMESTAMP] AUDIT (build): Bare except clause in $FILE_PATH" >> "$AUDIT_LOG"
        fi

        # Route files without rate limiting
        if echo "$FILE_PATH" | grep -qiE '(routes/|router|endpoint).*\.py$'; then
            FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")
            if echo "$FILE_CONTENT" | grep -qE '@(app|router)\.(get|post|put|patch|delete)\s*\('; then
                if ! echo "$FILE_CONTENT" | grep -qiE '@limiter\.limit|RateLimitMiddleware|rate_limit|slowapi|Depends\(.*rate'; then
                    echo "[$TIMESTAMP] AUDIT (build): Missing rate limiting in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi

            # Missing error handling in route handlers
            if echo "$FILE_CONTENT" | grep -qE '@(app|router)\.(get|post|put|patch|delete)\s*\('; then
                if ! echo "$FILE_CONTENT" | grep -qiE 'try:|except\s|HTTPException|exception_handler|@app\.exception'; then
                    echo "[$TIMESTAMP] AUDIT (build): Missing error handling in route handlers $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi
        fi

        # Unsafe CORS
        if grep -qiE 'allow_origins\s*=\s*\[\s*"\*"\s*\]|Access-Control-Allow-Origin.*\*' "$FILE_PATH" 2>/dev/null; then
            echo "[$TIMESTAMP] AUDIT (build): Unsafe CORS (allow all origins) in $FILE_PATH" >> "$AUDIT_LOG"
        fi
    fi

    # Migration warnings
    if echo "$FILE_PATH" | grep -qiE 'supabase/migrations/.*\.sql$'; then
        FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")

        # Missing RLS
        if echo "$FILE_CONTENT" | grep -qiE 'CREATE\s+TABLE'; then
            if ! echo "$FILE_CONTENT" | grep -qiE 'ALTER\s+TABLE.*ENABLE\s+ROW\s+LEVEL\s+SECURITY|CREATE\s+POLICY|ROW\s+LEVEL\s+SECURITY'; then
                echo "[$TIMESTAMP] AUDIT (build): Missing RLS policy in migration $FILE_PATH" >> "$AUDIT_LOG"
            fi
        fi

        # Unindexed FK
        if echo "$FILE_CONTENT" | grep -qiE 'REFERENCES\s'; then
            FK_COLUMNS=$(echo "$FILE_CONTENT" | grep -ioE '\w+\s+\w+\s+REFERENCES' | awk '{print $1}')
            if [[ -n "$FK_COLUMNS" ]]; then
                for col in $FK_COLUMNS; do
                    if ! echo "$FILE_CONTENT" | grep -qiE "CREATE\s+INDEX.*$col|INDEX.*\($col"; then
                        echo "[$TIMESTAMP] AUDIT (build): Unindexed foreign key '$col' in $FILE_PATH" >> "$AUDIT_LOG"
                    fi
                done
            fi
        fi
    fi

    # SELECT * without limit (frontend/backend)
    if echo "$FILE_PATH" | grep -qE '\.(ts|tsx|js|jsx|vue|py)$'; then
        if grep -qE '\.select\(\s*["\x27]\*["\x27]\s*\)' "$FILE_PATH" 2>/dev/null; then
            if ! grep -qE '\.limit\s*\(' "$FILE_PATH" 2>/dev/null; then
                echo "[$TIMESTAMP] AUDIT (build): SELECT * without .limit() in $FILE_PATH" >> "$AUDIT_LOG"
            fi
        fi
    fi

# ============================================================
# DEPLOY MODE: full enforcement with plain English messages
# ============================================================
elif [[ "$MODE" == "deploy" ]]; then

    # --------------------------------------------------------
    # TypeScript / Vue / JavaScript files
    # --------------------------------------------------------
    if echo "$FILE_PATH" | grep -qE '\.(ts|tsx|js|jsx|vue)$'; then

        # ESLint
        if command -v npx &>/dev/null && [[ -f "frontend/node_modules/.bin/eslint" || -f "node_modules/.bin/eslint" ]]; then
            ESLINT_OUTPUT=$(cd frontend 2>/dev/null && npx eslint --max-warnings=0 "../$FILE_PATH" 2>&1) || {
                ESLINT_EXIT=$?
                if [[ $ESLINT_EXIT -ne 0 ]]; then
                    BLOCKED=true
                    BLOCK_MESSAGES+=("I found code style issues that need fixing before deploying.")
                    echo "[$TIMESTAMP] BLOCKED: ESLint failed on $FILE_PATH" >> "$AUDIT_LOG"
                fi
            }
        fi

        # Console.log — block in deploy (exclude test files)
        if ! echo "$FILE_PATH" | grep -qE '(\.test\.|\.spec\.|__tests__/)'; then
            if grep -qE '\bconsole\.(log|debug)\b' "$FILE_PATH" 2>/dev/null; then
                BLOCKED=true
                BLOCK_MESSAGES+=("Console.log statements must be removed before deploying.")
                echo "[$TIMESTAMP] BLOCKED: console.log in deploy mode $FILE_PATH" >> "$AUDIT_LOG"
            fi
        fi

        # Run corresponding test file
        TEST_FILE=""
        if echo "$FILE_PATH" | grep -qE 'frontend/'; then
            BASE_NAME=$(basename "$FILE_PATH" | sed 's/\.\(ts\|tsx\|js\|jsx\|vue\)$//')
            TEST_FILE=$(find frontend/tests -name "${BASE_NAME}.test.*" -o -name "${BASE_NAME}.spec.*" 2>/dev/null | head -1)
            if [[ -n "$TEST_FILE" ]] && command -v npx &>/dev/null; then
                echo "[$TIMESTAMP] POST-EDIT: running test $TEST_FILE" >> "$AUDIT_LOG"
                cd frontend 2>/dev/null && npx vitest run "../$TEST_FILE" --reporter=verbose >> "../$AUDIT_LOG" 2>&1 || {
                    echo "[$TIMESTAMP] WARNING: Test $TEST_FILE failed" >> "../$AUDIT_LOG"
                }
                cd - &>/dev/null || true
            fi
        fi

        # Vue component enterprise checks
        if echo "$FILE_PATH" | grep -qE '\.vue$'; then
            FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")

            # Missing loading state
            if echo "$FILE_CONTENT" | grep -qE 'await\s|\.then\s*\(|useFetch|useAsyncData|useLazyFetch'; then
                if ! echo "$FILE_CONTENT" | grep -qiE 'loading|isLoading|pending|isFetching|skeleton|spinner'; then
                    BLOCKED=true
                    BLOCK_MESSAGES+=("This page needs a loading indicator so users know data is loading.")
                    echo "[$TIMESTAMP] BLOCKED: Missing loading state in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi

            # Missing error state
            if echo "$FILE_CONTENT" | grep -qE 'await\s|\.then\s*\(|useFetch|useAsyncData|useLazyFetch'; then
                if ! echo "$FILE_CONTENT" | grep -qiE 'error|isError|catch\s*\(|\.catch|onError|ErrorAlert|error-alert'; then
                    BLOCKED=true
                    BLOCK_MESSAGES+=("This page needs error handling so users see a message when something goes wrong.")
                    echo "[$TIMESTAMP] BLOCKED: Missing error state in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi

            # Missing empty state
            if echo "$FILE_CONTENT" | grep -qE 'v-for\s*='; then
                if ! echo "$FILE_CONTENT" | grep -qiE '\.length\s*===?\s*0|empty|no-data|no-results|EmptyState|empty-state'; then
                    BLOCKED=true
                    BLOCK_MESSAGES+=("This list needs an empty state for when there are no items.")
                    echo "[$TIMESTAMP] BLOCKED: Missing empty state for list in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi

            LINE_COUNT=$(file_line_count "$FILE_PATH")
            if [[ "$LINE_COUNT" -gt 200 ]]; then
                echo "[$TIMESTAMP] WARNING: Oversized component $FILE_PATH ($LINE_COUNT lines)" >> "$AUDIT_LOG"
            fi
        fi

        # SELECT * without limit (JS/TS)
        if grep -qE '\.select\(\s*["\x27]\*["\x27]\s*\)' "$FILE_PATH" 2>/dev/null; then
            if ! grep -qE '\.limit\s*\(' "$FILE_PATH" 2>/dev/null; then
                BLOCKED=true
                BLOCK_MESSAGES+=("This query selects all columns without a limit. Add .limit() to prevent unbounded results.")
                echo "[$TIMESTAMP] BLOCKED: SELECT * without .limit() in $FILE_PATH" >> "$AUDIT_LOG"
            fi
        fi
    fi

    # --------------------------------------------------------
    # Python files
    # --------------------------------------------------------
    if echo "$FILE_PATH" | grep -qE '\.py$'; then

        # Ruff linter
        if command -v ruff &>/dev/null; then
            RUFF_OUTPUT=$(ruff check "$FILE_PATH" 2>&1) || {
                BLOCKED=true
                BLOCK_MESSAGES+=("Python formatting issues need to be resolved before deploying.")
                echo "[$TIMESTAMP] BLOCKED: ruff check failed on $FILE_PATH" >> "$AUDIT_LOG"
            }

            ruff format --check "$FILE_PATH" >> "$AUDIT_LOG" 2>&1 || {
                echo "[$TIMESTAMP] WARNING: ruff format check failed on $FILE_PATH" >> "$AUDIT_LOG"
            }
        fi

        # Bandit security scan
        if command -v bandit &>/dev/null; then
            BANDIT_OUTPUT=$(bandit -ll "$FILE_PATH" 2>&1) || {
                BANDIT_EXIT=$?
                if [[ $BANDIT_EXIT -ne 0 ]] && echo "$BANDIT_OUTPUT" | grep -qiE 'Severity:\s*High'; then
                    BLOCKED=true
                    BLOCK_MESSAGES+=("High-severity security issue found — must be fixed before deploying.")
                    echo "[$TIMESTAMP] BLOCKED: bandit HIGH severity in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            }
        fi

        # Mypy type check
        if command -v mypy &>/dev/null; then
            MYPY_OUTPUT=$(mypy "$FILE_PATH" --ignore-missing-imports 2>&1) || {
                MYPY_EXIT=$?
                if [[ $MYPY_EXIT -ne 0 ]] && echo "$MYPY_OUTPUT" | grep -qE 'error:'; then
                    BLOCKED=true
                    BLOCK_MESSAGES+=("Type errors need to be fixed before deploying.")
                    echo "[$TIMESTAMP] BLOCKED: mypy errors in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            }
        fi

        # Bare except clause
        if grep -qE '^\s*except\s*:' "$FILE_PATH" 2>/dev/null; then
            BLOCKED=true
            BLOCK_MESSAGES+=("Bare 'except:' catches everything including system exits. Specify the exception type.")
            echo "[$TIMESTAMP] BLOCKED: bare except in $FILE_PATH" >> "$AUDIT_LOG"
        fi

        # Run corresponding test file
        if echo "$FILE_PATH" | grep -qE 'backend/'; then
            BASE_NAME=$(basename "$FILE_PATH" .py)
            TEST_FILE=$(find backend/tests -name "test_${BASE_NAME}.py" 2>/dev/null | head -1)
            if [[ -n "$TEST_FILE" ]] && command -v pytest &>/dev/null; then
                echo "[$TIMESTAMP] POST-EDIT: running test $TEST_FILE" >> "$AUDIT_LOG"
                cd backend 2>/dev/null && pytest "../$TEST_FILE" -v >> "../$AUDIT_LOG" 2>&1 || {
                    echo "[$TIMESTAMP] WARNING: Test $TEST_FILE failed" >> "../$AUDIT_LOG"
                }
                cd - &>/dev/null || true
            fi
        fi

        # Unsafe CORS
        if grep -qiE 'allow_origins\s*=\s*\[\s*"\*"\s*\]|Access-Control-Allow-Origin.*\*' "$FILE_PATH" 2>/dev/null; then
            BLOCKED=true
            BLOCK_MESSAGES+=("CORS is set to allow all origins. Restrict to your app's domain(s) before deploying.")
            echo "[$TIMESTAMP] BLOCKED: Unsafe CORS in $FILE_PATH" >> "$AUDIT_LOG"
        fi

        # Route file enterprise checks
        if echo "$FILE_PATH" | grep -qiE '(routes/|router|endpoint).*\.py$'; then
            FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")

            # Missing rate limiting
            if echo "$FILE_CONTENT" | grep -qE '@(app|router)\.(get|post|put|patch|delete)\s*\('; then
                if ! echo "$FILE_CONTENT" | grep -qiE '@limiter\.limit|RateLimitMiddleware|rate_limit|slowapi|Depends\(.*rate'; then
                    BLOCKED=true
                    BLOCK_MESSAGES+=("This API route needs rate limiting to prevent abuse.")
                    echo "[$TIMESTAMP] BLOCKED: Missing rate limiting in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi

            # Missing pagination
            if echo "$FILE_CONTENT" | grep -qiE '@(app|router)\.get\s*\(' && echo "$FILE_CONTENT" | grep -qiE 'list|all|index|search|fetch.*s\b'; then
                if ! echo "$FILE_CONTENT" | grep -qiE 'limit|offset|page|cursor|pagination|Pagination|skip'; then
                    BLOCKED=true
                    BLOCK_MESSAGES+=("This list endpoint needs pagination. Add limit/cursor parameters.")
                    echo "[$TIMESTAMP] BLOCKED: Missing pagination in list endpoint $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi

            # Missing soft-delete
            if echo "$FILE_CONTENT" | grep -qiE '@(app|router)\.(delete|post)\s*\(' && echo "$FILE_CONTENT" | grep -qiE 'delete|remove|destroy'; then
                if ! echo "$FILE_CONTENT" | grep -qiE 'deleted_at|soft.delete|is_deleted|mark.*deleted'; then
                    BLOCKED=true
                    BLOCK_MESSAGES+=("This delete endpoint removes data permanently. Use soft deletes (set deleted_at).")
                    echo "[$TIMESTAMP] BLOCKED: Hard delete instead of soft delete in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi

            # Missing error handling in route handlers
            if echo "$FILE_CONTENT" | grep -qE '@(app|router)\.(get|post|put|patch|delete)\s*\('; then
                if ! echo "$FILE_CONTENT" | grep -qiE 'try:|except\s|HTTPException|exception_handler|@app\.exception'; then
                    BLOCKED=true
                    BLOCK_MESSAGES+=("Route handlers need error handling (try/except or exception middleware).")
                    echo "[$TIMESTAMP] BLOCKED: Missing error handling in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi

            # Oversized handler warning
            HANDLER_LINES=$(grep -cE '^\s+(async\s+)?def\s' "$FILE_PATH" 2>/dev/null || echo "0")
            TOTAL_LINES=$(file_line_count "$FILE_PATH")
            if [[ "$HANDLER_LINES" -gt 0 ]]; then
                AVG_LINES=$((TOTAL_LINES / HANDLER_LINES))
                if [[ "$AVG_LINES" -gt 25 ]]; then
                    echo "[$TIMESTAMP] WARNING: Oversized route handlers in $FILE_PATH (~$AVG_LINES lines avg)" >> "$AUDIT_LOG"
                fi
            fi
        fi

        # Auth-related file checks
        if echo "$FILE_PATH" | grep -qiE '(auth|login|session|middleware).*\.py$'; then
            FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")

            # Missing auth guard
            if echo "$FILE_CONTENT" | grep -qE '@(app|router)\.(get|post|put|patch|delete)\s*\('; then
                if ! echo "$FILE_PATH" | grep -qiE 'login|register|signup|invite|health'; then
                    if ! echo "$FILE_CONTENT" | grep -qiE 'Depends\(.*auth|Depends\(.*current_user|Depends\(.*get_user|verify_token|require_auth|security'; then
                        BLOCKED=true
                        BLOCK_MESSAGES+=("This protected route needs an auth guard. Add Depends(get_current_user).")
                        echo "[$TIMESTAMP] BLOCKED: Missing auth guard in $FILE_PATH" >> "$AUDIT_LOG"
                    fi
                fi
            fi

            # User ID from request body
            if echo "$FILE_CONTENT" | grep -qiE 'body\.user_id|request\.json.*user_id|data\[.user_id.\]|payload\.user_id'; then
                if ! echo "$FILE_CONTENT" | grep -qiE 'current_user\.id|token\.sub|jwt.*user|auth\.uid'; then
                    BLOCKED=true
                    BLOCK_MESSAGES+=("User ID is read from request body (can be faked). Get it from the JWT token instead.")
                    echo "[$TIMESTAMP] BLOCKED: User ID from request body in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi
        fi

        # SELECT * without limit (Python)
        if grep -qE '\.select\(\s*["\x27]\*["\x27]\s*\)' "$FILE_PATH" 2>/dev/null; then
            if ! grep -qE '\.limit\s*\(' "$FILE_PATH" 2>/dev/null; then
                BLOCKED=true
                BLOCK_MESSAGES+=("This query selects all columns without a limit. Add .limit() to prevent unbounded results.")
                echo "[$TIMESTAMP] BLOCKED: SELECT * without .limit() in $FILE_PATH" >> "$AUDIT_LOG"
            fi
        fi
    fi

    # --------------------------------------------------------
    # --------------------------------------------------------
    # Azure-specific blocks (only when DEPLOY_TARGET=azure)
    # --------------------------------------------------------
    DEPLOY_TARGET_VAL=$(cat .env 2>/dev/null | grep '^DEPLOY_TARGET=' | cut -d= -f2 | tr -d '[:space:]' || echo "")
    if [[ "$DEPLOY_TARGET_VAL" == "azure" ]]; then

        # Block migrations that reference schemas other than APP_SCHEMA
        if echo "$FILE_PATH" | grep -qiE 'supabase/migrations/.*\.sql$'; then
            AZURE_APP_SCHEMA=$(cat .env 2>/dev/null | grep '^APP_SCHEMA=' | cut -d= -f2 | tr -d '[:space:]' || echo "")
            if [[ -n "$AZURE_APP_SCHEMA" ]]; then
                FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")
                if echo "$FILE_CONTENT" | grep -qiE 'SET\s+search_path\s+TO\s+'; then
                    OTHER=$(echo "$FILE_CONTENT" | grep -iE 'SET\s+search_path\s+TO\s+' \
                        | grep -v "$AZURE_APP_SCHEMA" | grep -v "public" || true)
                    if [[ -n "$OTHER" ]]; then
                        BLOCKED=true
                        BLOCK_MESSAGES+=("This migration sets search_path to a schema other than $AZURE_APP_SCHEMA. Each app must use only its own schema (APP_SCHEMA env var).")
                        echo "[$TIMESTAMP] BLOCKED (azure): Migration references wrong schema in $FILE_PATH" >> "$AUDIT_LOG"
                    fi
                fi
            fi
        fi

        # Block direct Google Auth API calls (must go through OAuth2 Proxy)
        if echo "$FILE_PATH" | grep -qE '\.(ts|tsx|js|jsx|vue|py)$'; then
            FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")
            if echo "$FILE_CONTENT" | grep -qiE 'accounts\.google\.com|oauth2\.googleapis\.com|googleapis\.com/auth'; then
                BLOCKED=true
                BLOCK_MESSAGES+=("Direct Google Auth API calls are not allowed in Azure mode. Authentication goes through the OAuth2 Proxy — the app receives the user email via a request header.")
                echo "[$TIMESTAMP] BLOCKED (azure): Direct Google Auth API call in $FILE_PATH" >> "$AUDIT_LOG"
            fi
        fi

        # Block Blob Storage access without APP_BLOB_CONTAINER scope
        if echo "$FILE_PATH" | grep -qE '\.(py)$'; then
            FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")
            if echo "$FILE_CONTENT" | grep -qiE 'BlobServiceClient|ContainerClient|BlobClient'; then
                if ! echo "$FILE_CONTENT" | grep -qiE 'BLOB_CONTAINER|APP_BLOB_CONTAINER|os\.environ|os\.getenv'; then
                    BLOCKED=true
                    BLOCK_MESSAGES+=("Azure Blob Storage access must use the app-scoped container from the BLOB_CONTAINER environment variable — never a hardcoded container name.")
                    echo "[$TIMESTAMP] BLOCKED (azure): Blob access without BLOB_CONTAINER scope in $FILE_PATH" >> "$AUDIT_LOG"
                fi
            fi
        fi

    fi

    # Migration file checks
    # --------------------------------------------------------
    if echo "$FILE_PATH" | grep -qiE 'supabase/migrations/.*\.sql$'; then
        FILE_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")

        # ALTER TABLE on existing table
        if echo "$FILE_CONTENT" | grep -qiE '^\s*ALTER\s+TABLE\b'; then
            TABLE_NAME=$(echo "$FILE_CONTENT" | grep -ioE 'ALTER\s+TABLE\s+\S+' | head -1 | awk '{print $3}')
            if [[ -n "$TABLE_NAME" ]] && ! echo "$FILE_CONTENT" | grep -qiE "CREATE\s+TABLE.*$TABLE_NAME"; then
                BLOCKED=true
                BLOCK_MESSAGES+=("This modifies an existing table with ALTER TABLE. Create a new migration file instead.")
                echo "[$TIMESTAMP] BLOCKED: ALTER TABLE on existing table in $FILE_PATH" >> "$AUDIT_LOG"
            fi
        fi

        # Missing RLS policy
        if echo "$FILE_CONTENT" | grep -qiE 'CREATE\s+TABLE'; then
            if ! echo "$FILE_CONTENT" | grep -qiE 'ALTER\s+TABLE.*ENABLE\s+ROW\s+LEVEL\s+SECURITY|CREATE\s+POLICY|ROW\s+LEVEL\s+SECURITY'; then
                BLOCKED=true
                BLOCK_MESSAGES+=("This table needs Row Level Security. Add ALTER TABLE ... ENABLE ROW LEVEL SECURITY and CREATE POLICY.")
                echo "[$TIMESTAMP] BLOCKED: Missing RLS in migration $FILE_PATH" >> "$AUDIT_LOG"
            fi
        fi

        # Unindexed FK
        if echo "$FILE_CONTENT" | grep -qiE 'REFERENCES\s'; then
            FK_COLUMNS=$(echo "$FILE_CONTENT" | grep -ioE '\w+\s+\w+\s+REFERENCES' | awk '{print $1}')
            if [[ -n "$FK_COLUMNS" ]]; then
                for col in $FK_COLUMNS; do
                    if ! echo "$FILE_CONTENT" | grep -qiE "CREATE\s+INDEX.*$col|INDEX.*\($col"; then
                        BLOCKED=true
                        BLOCK_MESSAGES+=("Foreign key column '$col' needs an index for performance.")
                        echo "[$TIMESTAMP] BLOCKED: Unindexed FK '$col' in $FILE_PATH" >> "$AUDIT_LOG"
                    fi
                done
            fi
        fi
    fi
fi

# ============================================================
# Report results
# ============================================================
if [[ "$BLOCKED" == true ]]; then
    echo "" >&2
    for msg in "${BLOCK_MESSAGES[@]}"; do
        echo "  $msg" >&2
        echo "" >&2
    done
    exit 2
fi

exit 0
