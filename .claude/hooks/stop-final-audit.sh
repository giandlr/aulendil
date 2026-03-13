#!/usr/bin/env bash
# Final audit on session stop — warnings only, never blocks (too late to undo)
# BUILD mode: only gitleaks scan
# DEPLOY mode: full audit (gitleaks, npm audit, pip-audit, TODO check, missing tests)
# Triggered on: Stop event
# Always exits 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/mode.sh"

AUDIT_LOG=".claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true

# Safety: any unexpected error exits cleanly
trap 'exit 0' ERR

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "" >> "$AUDIT_LOG"
echo "========================================" >> "$AUDIT_LOG"
echo "[$TIMESTAMP] FINAL AUDIT — Session Stop" >> "$AUDIT_LOG"
echo "========================================" >> "$AUDIT_LOG"

WARNINGS=0
MODE=$(get_mode)

# --- Early exit: skip if nothing has changed this session ---
if git rev-parse --is-inside-work-tree &>/dev/null; then
    CHANGED=$(git diff --name-only 2>/dev/null; git diff --name-only --cached 2>/dev/null)
    if [[ -z "$CHANGED" ]]; then
        echo "[$TIMESTAMP] SKIPPED: No changed files — nothing to audit" >> "$AUDIT_LOG"
        exit 0
    fi
fi

# --- Gitleaks full scan (always runs in both modes) ---
if command -v gitleaks &>/dev/null; then
    echo "Running gitleaks scan..." >&2
    GITLEAKS_OUTPUT=$(gitleaks detect --source=. 2>&1)
    GITLEAKS_EXIT=$?
    if [[ $GITLEAKS_EXIT -ne 0 ]]; then
        echo "WARNING: Gitleaks found potential secrets in the repository." >&2
        echo "$GITLEAKS_OUTPUT" | head -20 >&2
        echo "[$TIMESTAMP] WARNING: Gitleaks detected secrets" >> "$AUDIT_LOG"
        ((WARNINGS++))
    else
        echo "[$TIMESTAMP] OK: Gitleaks scan clean" >> "$AUDIT_LOG"
    fi
else
    echo "WARNING: gitleaks not installed. Install it for secret scanning: https://github.com/gitleaks/gitleaks#installing" >&2
    echo "[$TIMESTAMP] SKIPPED: gitleaks not installed" >> "$AUDIT_LOG"
fi

# --- DEPLOY mode only: full audit checks ---
if [[ "$MODE" == "deploy" ]]; then

    # --- npm audit ---
    if [[ -f "frontend/package-lock.json" ]] && command -v npm &>/dev/null; then
        echo "Running npm audit..." >&2
        NPM_AUDIT=$(cd frontend && npm audit --audit-level=high 2>&1)
        NPM_EXIT=$?
        if [[ $NPM_EXIT -ne 0 ]]; then
            echo "WARNING: npm audit found high-severity vulnerabilities in frontend dependencies." >&2
            echo "$NPM_AUDIT" | tail -10 >&2
            echo "[$TIMESTAMP] WARNING: npm audit found vulnerabilities" >> "$AUDIT_LOG"
            ((WARNINGS++))
        else
            echo "[$TIMESTAMP] OK: npm audit clean" >> "$AUDIT_LOG"
        fi
    fi

    # --- pip-audit ---
    if [[ -f "backend/requirements.txt" || -f "requirements.txt" ]]; then
        if command -v pip-audit &>/dev/null; then
            echo "Running pip-audit..." >&2
            REQ_FILE="requirements.txt"
            [[ -f "backend/requirements.txt" ]] && REQ_FILE="backend/requirements.txt"
            PIP_AUDIT=$(pip-audit -r "$REQ_FILE" 2>&1)
            PIP_EXIT=$?
            if [[ $PIP_EXIT -ne 0 ]]; then
                echo "WARNING: pip-audit found vulnerabilities in Python dependencies." >&2
                echo "$PIP_AUDIT" | tail -10 >&2
                echo "[$TIMESTAMP] WARNING: pip-audit found vulnerabilities" >> "$AUDIT_LOG"
                ((WARNINGS++))
            else
                echo "[$TIMESTAMP] OK: pip-audit clean" >> "$AUDIT_LOG"
            fi
        else
            echo "WARNING: pip-audit not installed. Install: pip install pip-audit" >&2
            echo "[$TIMESTAMP] SKIPPED: pip-audit not installed" >> "$AUDIT_LOG"
        fi
    fi

    # --- TODO/FIXME check in changed files ---
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only 2>/dev/null || echo "")
        if [[ -n "$CHANGED_FILES" ]]; then
            TODO_TOTAL=0
            TODO_FILES=""
            while IFS= read -r file; do
                if [[ -f "$file" ]]; then
                    COUNT=$(grep -ciE '\bTODO\b|\bFIXME\b' "$file" 2>/dev/null; true)
                    if [[ "$COUNT" -gt 0 ]]; then
                        TODO_TOTAL=$((TODO_TOTAL + COUNT))
                        TODO_FILES="$TODO_FILES  - $file ($COUNT markers)\n"
                    fi
                fi
            done <<< "$CHANGED_FILES"

            if [[ $TODO_TOTAL -gt 0 ]]; then
                echo "WARNING: $TODO_TOTAL TODO/FIXME markers found in changed files:" >&2
                echo -e "$TODO_FILES" >&2
                echo "[$TIMESTAMP] WARNING: $TODO_TOTAL TODO/FIXME in changed files" >> "$AUDIT_LOG"
                ((WARNINGS++))
            else
                echo "[$TIMESTAMP] OK: No TODO/FIXME in changed files" >> "$AUDIT_LOG"
            fi
        fi

        # --- Missing test files for new source files ---
        NEW_FILES=$(git diff --diff-filter=A --name-only HEAD 2>/dev/null || echo "")
        if [[ -n "$NEW_FILES" ]]; then
            MISSING_TESTS=""
            while IFS= read -r file; do
                # Skip test files, config files, migrations, docs
                if echo "$file" | grep -qE '(test_|\.test\.|\.spec\.|__pycache__|migrations/|docs/|\.claude/|\.config)'; then
                    continue
                fi
                # Only check source files
                if echo "$file" | grep -qE '\.(py|ts|tsx|js|jsx|vue)$'; then
                    BASE_NAME=$(basename "$file" | sed 's/\.\(py\|ts\|tsx\|js\|jsx\|vue\)$//')
                    TEST_EXISTS=false

                    # Check Python test
                    if echo "$file" | grep -qE '\.py$'; then
                        find backend/tests -name "test_${BASE_NAME}.py" 2>/dev/null | grep -q . && TEST_EXISTS=true
                    fi

                    # Check TS/Vue test
                    if echo "$file" | grep -qE '\.(ts|tsx|js|jsx|vue)$'; then
                        find frontend/tests -name "${BASE_NAME}.test.*" -o -name "${BASE_NAME}.spec.*" 2>/dev/null | grep -q . && TEST_EXISTS=true
                    fi

                    if [[ "$TEST_EXISTS" == false ]]; then
                        MISSING_TESTS="$MISSING_TESTS  - $file\n"
                    fi
                fi
            done <<< "$NEW_FILES"

            if [[ -n "$MISSING_TESTS" ]]; then
                echo "WARNING: New source files missing corresponding test files:" >&2
                echo -e "$MISSING_TESTS" >&2
                echo "[$TIMESTAMP] WARNING: New files missing tests" >> "$AUDIT_LOG"
                ((WARNINGS++))
            fi
        fi
    fi

else
    echo "[$TIMESTAMP] BUILD MODE: Skipped deploy-only audit checks (npm audit, pip-audit, TODO, missing tests)" >> "$AUDIT_LOG"
fi

# --- Final summary ---
echo "" >> "$AUDIT_LOG"
echo "[$TIMESTAMP] FINAL AUDIT COMPLETE ($MODE mode): $WARNINGS warning(s)" >> "$AUDIT_LOG"
echo "" >&2
echo "=== FINAL AUDIT COMPLETE ($MODE mode): $WARNINGS warning(s) ===" >&2

# Always exit 0 — stop hooks should never block (too late to undo)
exit 0
