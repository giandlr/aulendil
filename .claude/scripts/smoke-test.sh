#!/usr/bin/env bash
set -euo pipefail

# Smoke test: verifies the app starts and key pages load without errors.
# Used by the pipeline orchestrator for "app-starts" and "happy-path-works" gates.
#
# Exit 0 = all checks pass
# Exit 1 = one or more checks failed

FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
BACKEND_URL="${BACKEND_URL:-http://localhost:8000}"
GATE_LEVEL="${GATE_LEVEL:-mvp}"
RESULTS_FILE=".claude/tmp/smoke-results.json"

mkdir -p .claude/tmp
PASSED=0
FAILED=0
WARNED=0
CHECKS=()

check() {
    local name="$1"
    local url="$2"
    local expect_in_body="${3:-}"

    local http_code
    local body
    body=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null) || body="000"

    if [[ "$body" =~ ^[23] ]]; then
        if [[ -n "$expect_in_body" ]]; then
            local page_body
            page_body=$(curl -s "$url" 2>/dev/null)
            if echo "$page_body" | grep -qi "$expect_in_body"; then
                PASSED=$((PASSED + 1))
                CHECKS+=("{\"name\": \"$name\", \"status\": \"pass\", \"http\": $body}")
                echo "  PASS  $name (HTTP $body)"
                return 0
            else
                FAILED=$((FAILED + 1))
                CHECKS+=("{\"name\": \"$name\", \"status\": \"fail\", \"http\": $body, \"reason\": \"Expected content not found: $expect_in_body\"}")
                echo "  FAIL  $name (HTTP $body — missing expected content: $expect_in_body)"
                return 1
            fi
        fi
        PASSED=$((PASSED + 1))
        CHECKS+=("{\"name\": \"$name\", \"status\": \"pass\", \"http\": $body}")
        echo "  PASS  $name (HTTP $body)"
    else
        FAILED=$((FAILED + 1))
        CHECKS+=("{\"name\": \"$name\", \"status\": \"fail\", \"http\": $body}")
        echo "  FAIL  $name (HTTP $body)"
    fi
}

check_no_error_banner() {
    local name="$1"
    local url="$2"

    local page_body
    page_body=$(curl -s "$url" 2>/dev/null) || page_body=""

    # Check for the info banner about missing database connection
    # In build/mvp: this is fine (warn only) — the app works without a database
    # In team/production: this must be fixed before sharing
    if echo "$page_body" | grep -qi "without a database\|not configured\|Setup needed"; then
        if [[ "$GATE_LEVEL" == "team" || "$GATE_LEVEL" == "production" ]]; then
            FAILED=$((FAILED + 1))
            CHECKS+=("{\"name\": \"$name\", \"status\": \"fail\", \"reason\": \"Database not connected — required for team/production\"}")
            echo "  FAIL  $name (database not connected — required at $GATE_LEVEL gate)"
            return 1
        else
            WARNED=$((WARNED + 1))
            PASSED=$((PASSED + 1))
            CHECKS+=("{\"name\": \"$name\", \"status\": \"warn\", \"reason\": \"Running without database — fine for building\"}")
            echo "  WARN  $name (no database — OK for building, needed for deploy)"
            return 0
        fi
    fi

    # Check for real errors (these always fail)
    if echo "$page_body" | grep -qiE "500 Internal|Server Error|Unhandled Exception|FATAL"; then
        FAILED=$((FAILED + 1))
        CHECKS+=("{\"name\": \"$name\", \"status\": \"fail\", \"reason\": \"Page contains error message\"}")
        echo "  FAIL  $name (page contains error)"
        return 1
    fi

    PASSED=$((PASSED + 1))
    CHECKS+=("{\"name\": \"$name\", \"status\": \"pass\"}")
    echo "  PASS  $name (no errors detected)"
}

echo ""
echo "Smoke Test"
echo "──────────────────────────────────────────"
echo ""

# Backend checks
echo "Backend ($BACKEND_URL):"
check "health-endpoint" "$BACKEND_URL/api/health"
check "api-docs" "$BACKEND_URL/docs"
echo ""

# Frontend checks
echo "Frontend ($FRONTEND_URL):"
check "home-page" "$FRONTEND_URL"
check_no_error_banner "home-no-errors" "$FRONTEND_URL"
check "projects-page" "$FRONTEND_URL/projects"
check_no_error_banner "projects-no-errors" "$FRONTEND_URL/projects"
echo ""

# Summary
echo "──────────────────────────────────────────"
if [[ $WARNED -gt 0 ]]; then
    echo "Results: $PASSED passed, $FAILED failed, $WARNED warnings"
else
    echo "Results: $PASSED passed, $FAILED failed"
fi
echo ""

# Write results
CHECKS_JSON=$(printf '%s\n' "${CHECKS[@]}" | paste -sd',' -)
cat > "$RESULTS_FILE" << RESULT_EOF
{
  "total": $((PASSED + FAILED)),
  "passed": $PASSED,
  "failed": $FAILED,
  "checks": [$CHECKS_JSON]
}
RESULT_EOF

if [[ $FAILED -gt 0 ]]; then
    echo "Smoke test FAILED — $FAILED check(s) need attention."
    exit 1
else
    echo "Smoke test PASSED."
    exit 0
fi
