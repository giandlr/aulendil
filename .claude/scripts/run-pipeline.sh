#!/usr/bin/env bash
set -uo pipefail

# Master CI/CD pipeline orchestrator
# Runs all test stages in parallel, then gates on Opus review
# On success, writes changelog entry automatically
# Exit 0 = PIPELINE PASSED, Exit 1 = PIPELINE FAILED

PIPELINE_START=$(date +%s)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "═══════════════════════════════════════════════════════════"
echo " CI/CD PIPELINE — $TIMESTAMP"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Ensure tmp directory exists
mkdir -p .claude/tmp

# Track stage results
declare -a FAILED_STAGES=()
declare -A STAGE_PIDS=()
declare -A STAGE_STATUS=()

# ============================================================
# Stage 1-4: Run all test stages IN PARALLEL
# ============================================================

echo "Stage 1-4: Running test suites in parallel..."
echo ""

# Unit tests
(
    echo "[UNIT] Starting unit tests..."
    if command -v pytest &>/dev/null && [[ -d "backend/tests" ]]; then
        cd backend && python -m pytest \
            --cov=. \
            --cov-report=json:../.claude/tmp/backend-coverage.json \
            --cov-report=term-missing \
            -v --tb=short \
            2>&1 | tee ../.claude/tmp/backend-unit-output.txt
        BACKEND_EXIT=${PIPESTATUS[0]}
    else
        BACKEND_EXIT=0
        echo '{"status": "SKIP", "reason": "pytest not found or no backend/tests directory"}' > .claude/tmp/backend-unit-output.txt
    fi

    if command -v npx &>/dev/null && [[ -f "frontend/package.json" ]]; then
        cd frontend 2>/dev/null && npx vitest run --coverage --reporter=verbose \
            2>&1 | tee ../.claude/tmp/frontend-unit-output.txt
        FRONTEND_EXIT=${PIPESTATUS[0]}
    else
        FRONTEND_EXIT=0
        echo '{"status": "SKIP", "reason": "vitest not found or no frontend/package.json"}' > .claude/tmp/frontend-unit-output.txt
    fi

    # Write combined results
    if [[ ${BACKEND_EXIT:-0} -eq 0 && ${FRONTEND_EXIT:-0} -eq 0 ]]; then
        echo '{"stage": "unit-tests", "overall_status": "PASS"}' > .claude/tmp/unit-results.json
        exit 0
    else
        echo '{"stage": "unit-tests", "overall_status": "FAIL"}' > .claude/tmp/unit-results.json
        exit 1
    fi
) &
STAGE_PIDS[unit]=$!

# UI tests
(
    echo "[UI] Starting e2e tests..."
    if command -v npx &>/dev/null && [[ -f "frontend/playwright.config.ts" || -f "frontend/playwright.config.js" ]]; then
        # Pre-flight: check if app is running
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
        if [[ "$HTTP_STATUS" == "000" || "$HTTP_STATUS" == "0" ]]; then
            echo '{"stage": "ui-tests", "overall_status": "SKIP", "reason": "App not running on localhost:3000"}' > .claude/tmp/ui-results.json
            exit 0
        fi
        cd frontend && npx playwright test --reporter=json \
            2>&1 | tee ../.claude/tmp/playwright-output.txt
        PW_EXIT=${PIPESTATUS[0]}
        if [[ $PW_EXIT -eq 0 ]]; then
            echo '{"stage": "ui-tests", "overall_status": "PASS"}' > .claude/tmp/ui-results.json
            exit 0
        else
            echo '{"stage": "ui-tests", "overall_status": "FAIL"}' > .claude/tmp/ui-results.json
            exit 1
        fi
    else
        echo '{"stage": "ui-tests", "overall_status": "SKIP", "reason": "Playwright not configured"}' > .claude/tmp/ui-results.json
        exit 0
    fi
) &
STAGE_PIDS[ui]=$!

# Integration tests
(
    echo "[INTEGRATION] Starting integration tests..."
    if command -v pytest &>/dev/null && [[ -d "backend/tests" ]]; then
        cd backend && python -m pytest \
            tests/integration/ \
            -v --tb=short \
            2>&1 | tee ../.claude/tmp/integration-output.txt
        INT_EXIT=${PIPESTATUS[0]}
        if [[ $INT_EXIT -eq 0 ]]; then
            echo '{"stage": "integration-tests", "overall_status": "PASS"}' > .claude/tmp/integration-results.json
            exit 0
        else
            echo '{"stage": "integration-tests", "overall_status": "FAIL"}' > .claude/tmp/integration-results.json
            exit 1
        fi
    else
        echo '{"stage": "integration-tests", "overall_status": "SKIP", "reason": "No integration tests found"}' > .claude/tmp/integration-results.json
        exit 0
    fi
) &
STAGE_PIDS[integration]=$!

# Performance tests
(
    echo "[PERF] Starting performance tests..."
    K6_STATUS="SKIP"
    LH_STATUS="SKIP"

    # k6 load tests
    if command -v k6 &>/dev/null; then
        K6_SCRIPT=$(find . -path "*/k6/*.js" -o -path "*/k6/*.ts" 2>/dev/null | head -1)
        if [[ -n "$K6_SCRIPT" ]]; then
            k6 run --summary-export=.claude/tmp/k6-export.json "$K6_SCRIPT" \
                2>&1 | tee .claude/tmp/k6-output.txt
            [[ ${PIPESTATUS[0]} -eq 0 ]] && K6_STATUS="PASS" || K6_STATUS="FAIL"
        fi
    fi

    # Lighthouse
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
    if [[ "$HTTP_STATUS" != "000" && "$HTTP_STATUS" != "0" ]]; then
        if npx --yes @lhci/cli --version &>/dev/null 2>&1; then
            npx --yes @lhci/cli collect --url=http://localhost:3000 --numberOfRuns=1 \
                2>&1 | tee .claude/tmp/lighthouse-output.txt
            [[ ${PIPESTATUS[0]} -eq 0 ]] && LH_STATUS="PASS" || LH_STATUS="FAIL"
        fi
    fi

    # Write results
    OVERALL="PASS"
    [[ "$K6_STATUS" == "FAIL" || "$LH_STATUS" == "FAIL" ]] && OVERALL="FAIL"
    [[ "$K6_STATUS" == "SKIP" && "$LH_STATUS" == "SKIP" ]] && OVERALL="SKIP"
    echo "{\"stage\": \"performance\", \"k6\": \"$K6_STATUS\", \"lighthouse\": \"$LH_STATUS\", \"overall_status\": \"$OVERALL\"}" > .claude/tmp/k6-summary.json
    [[ "$OVERALL" == "FAIL" ]] && exit 1 || exit 0
) &
STAGE_PIDS[perf]=$!

echo "  Unit tests:       PID ${STAGE_PIDS[unit]}"
echo "  UI tests:         PID ${STAGE_PIDS[ui]}"
echo "  Integration:      PID ${STAGE_PIDS[integration]}"
echo "  Performance:      PID ${STAGE_PIDS[perf]}"
echo ""

# ============================================================
# Wait for all stages and collect results
# ============================================================

for stage in unit ui integration perf; do
    wait "${STAGE_PIDS[$stage]}" 2>/dev/null
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 0 ]]; then
        STAGE_STATUS[$stage]="PASS"
        echo "  ✓ $stage: PASS"
    else
        STAGE_STATUS[$stage]="FAIL"
        FAILED_STAGES+=("$stage")
        echo "  ✗ $stage: FAIL (exit $EXIT_CODE)"
    fi
done

echo ""

# ============================================================
# Gate Decision
# ============================================================

if [[ ${#FAILED_STAGES[@]} -gt 0 ]]; then
    echo "═══════════════════════════════════════════════════════════"
    echo " GATE: TEST STAGES FAILED — SKIPPING OPUS REVIEW"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Failed stages: ${FAILED_STAGES[*]}"
    echo ""
    echo "Fix the failing tests before the pipeline can proceed."

    PIPELINE_END=$(date +%s)
    DURATION=$((PIPELINE_END - PIPELINE_START))

    # Write results
    cat > .claude/tmp/pipeline-results.md << RESULTS_EOF
═══ PIPELINE RESULTS ══════════════════════════
Timestamp:     $TIMESTAMP
Duration:      ${DURATION}s

Unit Tests:    ${STAGE_STATUS[unit]}
UI Tests:      ${STAGE_STATUS[ui]}
Integration:   ${STAGE_STATUS[integration]}
Performance:   ${STAGE_STATUS[perf]}

Opus Review:   SKIPPED (test stages failed)
Blockers:      N/A
Advisories:    N/A

GATE DECISION: PIPELINE FAILED
═══════════════════════════════════════════════
RESULTS_EOF

    echo ""
    cat .claude/tmp/pipeline-results.md
    exit 1
fi

# ============================================================
# Stage 5: Opus Code Review (all tests passed)
# ============================================================

echo "═══════════════════════════════════════════════════════════"
echo " ALL TESTS PASSED — Proceeding to Opus Code Review"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Build the review payload
echo "Building review payload..."
bash .claude/scripts/build-review-payload.sh
echo ""

# Invoke the Opus reviewer
echo "Invoking Opus reviewer..."
bash .claude/scripts/invoke-opus-reviewer.sh
OPUS_EXIT=$?

OPUS_STATUS="APPROVED"
[[ $OPUS_EXIT -ne 0 ]] && OPUS_STATUS="CHANGES REQUIRED"

# ============================================================
# Final Report
# ============================================================

PIPELINE_END=$(date +%s)
DURATION=$((PIPELINE_END - PIPELINE_START))

OVERALL_DECISION="PIPELINE PASSED"
FINAL_EXIT=0
if [[ $OPUS_EXIT -ne 0 ]]; then
    OVERALL_DECISION="PIPELINE FAILED"
    FINAL_EXIT=1
fi

cat > .claude/tmp/pipeline-results.md << RESULTS_EOF
═══ PIPELINE RESULTS ══════════════════════════
Timestamp:     $TIMESTAMP
Duration:      ${DURATION}s

Unit Tests:    ${STAGE_STATUS[unit]}
UI Tests:      ${STAGE_STATUS[ui]}
Integration:   ${STAGE_STATUS[integration]}
Performance:   ${STAGE_STATUS[perf]}

Opus Review:   $OPUS_STATUS
GATE DECISION: $OVERALL_DECISION
═══════════════════════════════════════════════
RESULTS_EOF

echo ""
echo ""
cat .claude/tmp/pipeline-results.md

# ============================================================
# Changelog Update (only on pipeline pass)
# ============================================================

if [[ $FINAL_EXIT -eq 0 ]]; then
    echo ""
    echo "Pipeline passed — updating changelog..."
    if [[ -f ".claude/scripts/write-changelog-entry.sh" ]]; then
        bash .claude/scripts/write-changelog-entry.sh || {
            echo "WARNING: Changelog update failed. This does not affect the pipeline result." >&2
            echo "The pipeline still PASSED. Changelog can be updated manually." >&2
        }
    else
        echo "WARNING: write-changelog-entry.sh not found. Skipping changelog update." >&2
    fi
fi

exit $FINAL_EXIT
