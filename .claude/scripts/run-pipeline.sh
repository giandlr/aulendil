#!/usr/bin/env bash
set -uo pipefail
# Debug mode
[[ "${AULENDIL_DEBUG:-}" == "1" ]] && set -x

# Master CI/CD pipeline orchestrator — gate-level aware
# Usage: bash .claude/scripts/run-pipeline.sh [mvp|team|production]
# Reads .claude/deploy-gates.json for stage requirements per gate level
# Exit 0 = PIPELINE PASSED, Exit 1 = PIPELINE FAILED

GATE_LEVEL="${1:-production}"
DEPLOY_TARGET="vercel"
PIPELINE_START=$(date +%s)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Set deploy mode, restore build mode on exit
echo "deploy:$$" > .claude/mode
trap 'echo "build" > .claude/mode; rm -f .claude/tmp/stage-pids.txt' EXIT

# Clean tmp directory
rm -rf .claude/tmp
mkdir -p .claude/tmp

echo "==========================================================="
echo " CI/CD PIPELINE — $TIMESTAMP"
echo " Gate level:     $GATE_LEVEL"
echo " Deploy target:  $DEPLOY_TARGET"
echo "==========================================================="
echo ""

# Read gate config
DEPLOY_GATES=".claude/deploy-gates.json"
if [[ ! -f "$DEPLOY_GATES" ]]; then
    echo "ERROR: $DEPLOY_GATES not found" >&2
    exit 1
fi

# Check if a stage is required for current gate + target
# Checks common.requires first, then target-specific requires
stage_required() {
    local stage="$1"
    if command -v jq &>/dev/null; then
        # Check common requires
        if jq -e ".\"$GATE_LEVEL\".common.requires | index(\"$stage\")" "$DEPLOY_GATES" &>/dev/null; then
            return 0
        fi
        # Check target-specific requires
        if jq -e ".\"$GATE_LEVEL\".\"$DEPLOY_TARGET\".requires | index(\"$stage\")" "$DEPLOY_GATES" &>/dev/null; then
            return 0
        fi
        return 1
    fi
    # Fallback: grep-based check against both sections
    local gate_block
    gate_block=$(grep -A 60 "\"$GATE_LEVEL\"" "$DEPLOY_GATES" 2>/dev/null | head -60)
    echo "$gate_block" | grep -q "\"$stage\""
}

# Track stage results (bash 3.2 compatible — no associative arrays)
FAILED_STAGES=()
# STAGE_PID_<name> and STAGE_STATUS_<name> set dynamically below
SPAWNED_STAGES=()

# ===========================================================
# Stage: Security Scan (always runs)
# ===========================================================
echo "Running security scan..."
(
    bash .claude/scripts/security-scan.sh > .claude/tmp/security-output.txt 2>&1
) &
STAGE_PID_security=$!
SPAWNED_STAGES+=("security")

# ===========================================================
# Stage: Smoke Test (mvp and above)
# ===========================================================
if stage_required "app-starts" || stage_required "happy-path-works"; then
    echo "Running smoke tests..."
    (
        GATE_LEVEL="$GATE_LEVEL" bash .claude/scripts/smoke-test.sh > .claude/tmp/smoke-output.txt 2>&1
    ) &
    STAGE_PID_smoke=$!
    SPAWNED_STAGES+=("smoke")
else
    STAGE_STATUS_smoke="SKIP"
fi

# ===========================================================
# Stage: Unit Tests (team and above)
# ===========================================================
if stage_required "unit-tests"; then
    echo "Running unit tests..."
    (
        BACKEND_EXIT=0
        FRONTEND_EXIT=0

        if command -v pytest &>/dev/null && [[ -d "backend/tests" ]]; then
            cd backend && python -m pytest \
                --cov=. \
                --cov-report=json:../.claude/tmp/backend-coverage.json \
                --cov-report=term-missing \
                -v --tb=short \
                2>&1 | tee ../.claude/tmp/backend-unit-output.txt
            BACKEND_EXIT=${PIPESTATUS[0]}
            cd ..
        fi

        if command -v npx &>/dev/null && [[ -f "frontend/package.json" ]]; then
            cd frontend && npx vitest run --coverage --reporter=verbose \
                2>&1 | tee ../.claude/tmp/frontend-unit-output.txt
            FRONTEND_EXIT=${PIPESTATUS[0]}
            cd ..
        fi

        if [[ ${BACKEND_EXIT:-0} -eq 0 && ${FRONTEND_EXIT:-0} -eq 0 ]]; then
            echo '{"stage": "unit-tests", "overall_status": "PASS"}' > .claude/tmp/unit-results.json
            exit 0
        else
            echo '{"stage": "unit-tests", "overall_status": "FAIL"}' > .claude/tmp/unit-results.json
            exit 1
        fi
    ) &
    STAGE_PID_unit=$!
    SPAWNED_STAGES+=("unit")
else
    STAGE_STATUS_unit="SKIP"
fi

# ===========================================================
# Stage: Integration Tests (production only)
# ===========================================================
if stage_required "integration-tests"; then
    echo "Running integration tests..."
    (
        if command -v pytest &>/dev/null && [[ -d "backend/tests/integration" ]]; then
            cd backend && python -m pytest tests/integration/ -v --tb=short \
                2>&1 | tee ../.claude/tmp/integration-output.txt
            if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
                echo '{"stage": "integration-tests", "overall_status": "PASS"}' > .claude/tmp/integration-results.json
                exit 0
            else
                echo '{"stage": "integration-tests", "overall_status": "FAIL"}' > .claude/tmp/integration-results.json
                exit 1
            fi
        else
            echo '{"stage": "integration-tests", "overall_status": "SKIP"}' > .claude/tmp/integration-results.json
            exit 0
        fi
    ) &
    STAGE_PID_integration=$!
    SPAWNED_STAGES+=("integration")
else
    STAGE_STATUS_integration="SKIP"
fi

# ===========================================================
# Stage: UI Tests (team and above)
# ===========================================================
if stage_required "ui-tests"; then
    echo "Running UI tests..."
    (
        if command -v npx &>/dev/null && [[ -f "frontend/playwright.config.ts" || -f "frontend/playwright.config.js" ]]; then
            cd frontend && npx playwright test --reporter=json \
                2>&1 | tee ../.claude/tmp/playwright-output.txt
            if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
                echo '{"stage": "ui-tests", "overall_status": "PASS"}' > .claude/tmp/ui-results.json
                exit 0
            else
                echo '{"stage": "ui-tests", "overall_status": "FAIL"}' > .claude/tmp/ui-results.json
                exit 1
            fi
        else
            echo '{"stage": "ui-tests", "overall_status": "SKIP"}' > .claude/tmp/ui-results.json
            exit 0
        fi
    ) &
    STAGE_PID_ui=$!
    SPAWNED_STAGES+=("ui")
else
    STAGE_STATUS_ui="SKIP"
fi

# ===========================================================
# Stage: Performance (production only)
# ===========================================================
if stage_required "performance"; then
    echo "Running performance tests..."
    (
        K6_STATUS="SKIP"
        LH_STATUS="SKIP"

        if command -v k6 &>/dev/null; then
            K6_SCRIPT=$(find . -path "*/k6/*.js" -o -path "*/k6/*.ts" 2>/dev/null | head -1)
            if [[ -n "$K6_SCRIPT" ]]; then
                k6 run --summary-export=.claude/tmp/k6-export.json "$K6_SCRIPT" \
                    2>&1 | tee .claude/tmp/k6-output.txt
                [[ ${PIPESTATUS[0]} -eq 0 ]] && K6_STATUS="PASS" || K6_STATUS="FAIL"
            fi
        fi

        PERF_URL="${FRONTEND_URL:-http://localhost:3000}"
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$PERF_URL" 2>/dev/null || echo "000")
        if [[ "$HTTP_STATUS" != "000" && "$HTTP_STATUS" != "0" ]]; then
            if npx --yes @lhci/cli --version &>/dev/null 2>&1; then
                npx --yes @lhci/cli collect --url="$PERF_URL" --numberOfRuns=1 \
                    2>&1 | tee .claude/tmp/lighthouse-output.txt
                [[ ${PIPESTATUS[0]} -eq 0 ]] && LH_STATUS="PASS" || LH_STATUS="FAIL"
            fi
        fi

        OVERALL="PASS"
        [[ "$K6_STATUS" == "FAIL" || "$LH_STATUS" == "FAIL" ]] && OVERALL="FAIL"
        [[ "$K6_STATUS" == "SKIP" && "$LH_STATUS" == "SKIP" ]] && OVERALL="SKIP"
        printf '{"stage":"performance","k6":"%s","lighthouse":"%s","overall_status":"%s"}' \
            "$K6_STATUS" "$LH_STATUS" "$OVERALL" > .claude/tmp/k6-summary.json
        [[ "$OVERALL" == "FAIL" ]] && exit 1 || exit 0
    ) &
    STAGE_PID_perf=$!
    SPAWNED_STAGES+=("perf")
else
    STAGE_STATUS_perf="SKIP"
fi

# ===========================================================
# Stage: Tier 1 Enterprise Feature Check (production only)
# ===========================================================
if stage_required "tier1-enterprise"; then
    echo "Running Tier 1 enterprise feature check..."
    (
        T1_ISSUES=0

        # RBAC migration — search by content, not filename
        RBAC_FOUND=false
        if [[ -d "supabase/migrations" ]]; then
            for mig in supabase/migrations/*.sql; do
                [[ ! -f "$mig" ]] && continue
                if grep -qiE 'CREATE\s+TABLE.*\broles\b' "$mig" 2>/dev/null && \
                   grep -qiE 'CREATE\s+TABLE.*\buser_roles\b' "$mig" 2>/dev/null; then
                    RBAC_FOUND=true
                    echo "  + RBAC migration found: $(basename "$mig")"
                    break
                fi
            done
        fi
        if ! $RBAC_FOUND; then
            echo "  x Missing RBAC migration (need roles + user_roles tables)"
            T1_ISSUES=$((T1_ISSUES + 1))
        fi

        # Health endpoint
        HEALTH_FOUND=false
        if grep -rqlE '@(app|router)\.(get|route).*["\x27]/health["\x27]' backend/ 2>/dev/null; then
            HEALTH_FOUND=true
        fi
        if ! $HEALTH_FOUND; then
            echo "  x Missing health endpoint (GET /health)"
            T1_ISSUES=$((T1_ISSUES + 1))
        fi

        # RLS on all migration tables
        if [[ -d "supabase/migrations" ]]; then
            for mig in supabase/migrations/*.sql; do
                [[ ! -f "$mig" ]] && continue
                if grep -qiE 'CREATE\s+TABLE' "$mig" 2>/dev/null; then
                    if ! grep -qiE 'ENABLE\s+ROW\s+LEVEL\s+SECURITY|CREATE\s+POLICY' "$mig" 2>/dev/null; then
                        echo "  x Missing RLS in migration: $(basename "$mig")"
                        T1_ISSUES=$((T1_ISSUES + 1))
                    fi
                fi
            done
        fi

        # RBAC middleware
        if [[ ! -f "backend/middleware/rbac.py" ]]; then
            echo "  x Missing RBAC middleware (backend/middleware/rbac.py)"
            T1_ISSUES=$((T1_ISSUES + 1))
        fi

        # Rate limiting (check for slowapi or similar)
        RATE_LIMIT_FOUND=false
        if grep -rqlE 'slowapi|Limiter|RateLimitMiddleware|rate.limit' backend/ 2>/dev/null; then
            RATE_LIMIT_FOUND=true
        fi
        if ! $RATE_LIMIT_FOUND; then
            echo "  x Missing rate limiting in backend"
            T1_ISSUES=$((T1_ISSUES + 1))
        fi

        # Error pages (framework-aware)
        if [[ -d "frontend" ]]; then
            FE_FRAMEWORK="nuxt"
            [[ -f ".env" ]] && FE_FRAMEWORK=$(grep -E "^FRONTEND_FRAMEWORK=" .env 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"' | tr -d "'" || echo "nuxt")
            [[ -z "$FE_FRAMEWORK" ]] && FE_FRAMEWORK="nuxt"

            if [[ "$FE_FRAMEWORK" == "next" ]]; then
                if [[ ! -f "frontend/app/error.tsx" ]] && ! grep -rqlE 'error\.tsx' frontend/app/ 2>/dev/null; then
                    echo "  x Missing error page (frontend/app/error.tsx)"
                    T1_ISSUES=$((T1_ISSUES + 1))
                fi
            else
                if [[ ! -f "frontend/error.vue" ]] && ! grep -rqlE 'NuxtErrorBoundary|error\.vue' frontend/ 2>/dev/null; then
                    echo "  x Missing error page (frontend/error.vue)"
                    T1_ISSUES=$((T1_ISSUES + 1))
                fi
            fi
        fi

        # Form validation (framework-aware)
        if [[ -d "frontend" ]]; then
            FORM_VAL_FOUND=false
            if [[ "${FE_FRAMEWORK:-nuxt}" == "next" ]]; then
                if grep -rqlE 'react-hook-form|useForm|zodResolver|z\.object|z\.string' frontend/ 2>/dev/null; then
                    FORM_VAL_FOUND=true
                fi
            else
                if grep -rqlE 'vee-validate|useForm|useField|z\.object|z\.string' frontend/ 2>/dev/null; then
                    FORM_VAL_FOUND=true
                fi
            fi
            if ! $FORM_VAL_FOUND; then
                echo "  x Missing form validation in frontend"
                T1_ISSUES=$((T1_ISSUES + 1))
            fi
        fi

        # CORS explicit allowlist (no wildcard in production)
        if grep -rqE 'allow_origins.*\[.*"\*"' backend/ 2>/dev/null; then
            echo "  x CORS wildcard (*) found — must use explicit origin allowlist for production"
            T1_ISSUES=$((T1_ISSUES + 1))
        fi

        if [[ $T1_ISSUES -eq 0 ]]; then
            echo '{"stage": "tier1-enterprise", "overall_status": "PASS"}' > .claude/tmp/tier1-results.json
            echo "  Tier 1 enterprise check: PASS"
            exit 0
        else
            echo '{"stage": "tier1-enterprise", "overall_status": "FAIL", "issues": '"$T1_ISSUES"'}' > .claude/tmp/tier1-results.json
            echo "  Tier 1 enterprise check: FAIL ($T1_ISSUES issues)"
            exit 1
        fi
    ) &
    STAGE_PID_tier1=$!
    SPAWNED_STAGES+=("tier1")
else
    STAGE_STATUS_tier1="SKIP"
fi

# ===========================================================
# Stage: Mobile Tests (when mobile/ exists)
# ===========================================================
if [[ -d "mobile" ]] && stage_required "unit-tests"; then
    echo "Running mobile tests..."
    (
        MOBILE_EXIT=0
        if command -v flutter &>/dev/null; then
            cd mobile && flutter test --coverage \
                2>&1 | tee ../.claude/tmp/mobile-test-output.txt
            MOBILE_EXIT=${PIPESTATUS[0]}
            cd ..

            # Run flutter analyze
            cd mobile && flutter analyze \
                2>&1 | tee -a ../.claude/tmp/mobile-test-output.txt
            ANALYZE_EXIT=${PIPESTATUS[0]}
            cd ..

            if [[ $MOBILE_EXIT -eq 0 && $ANALYZE_EXIT -eq 0 ]]; then
                echo '{"stage": "mobile-tests", "overall_status": "PASS"}' > .claude/tmp/mobile-results.json
                exit 0
            else
                echo '{"stage": "mobile-tests", "overall_status": "FAIL"}' > .claude/tmp/mobile-results.json
                exit 1
            fi
        else
            echo '{"stage": "mobile-tests", "overall_status": "SKIP", "reason": "flutter not found"}' > .claude/tmp/mobile-results.json
            exit 0
        fi
    ) &
    STAGE_PID_mobile=$!
    SPAWNED_STAGES+=("mobile")
else
    STAGE_STATUS_mobile="SKIP"
fi

# ===========================================================
# Wait for all stages
# ===========================================================
echo ""
echo "Waiting for stages to complete..."
echo ""

# Wait for spawned stages first (data-driven)
for stage in "${SPAWNED_STAGES[@]}"; do
    pid_var="STAGE_PID_${stage}"
    pid="${!pid_var:-}"
    if [[ -n "$pid" ]]; then
        wait "$pid" 2>/dev/null
        EXIT_CODE=$?
        if [[ $EXIT_CODE -eq 0 ]]; then
            eval "STAGE_STATUS_${stage}=PASS"
            echo "  + $stage: PASS"
        else
            eval "STAGE_STATUS_${stage}=FAIL"
            FAILED_STAGES+=("$stage")
            echo "  x $stage: FAIL (exit $EXIT_CODE)"
        fi
    fi
done

# Report skipped stages
for stage in security smoke unit integration ui perf tier1 mobile; do
    status_var="STAGE_STATUS_${stage}"
    if [[ -z "${!status_var:-}" ]]; then
        echo "  - $stage: SKIP"
    fi
done

echo ""

# ===========================================================
# RBAC Verification (team and above — runs before gate decision)
# ===========================================================

if stage_required "rbac-check"; then
    echo ""
    echo "Verifying RBAC setup..."
    RBAC_OK=true

    if [[ -f "supabase/migrations/00000000000001_rbac.sql" ]]; then
        echo "  + RBAC migration exists"
    else
        echo "  x RBAC migration not found"
        RBAC_OK=false
    fi

    if [[ -f "backend/middleware/rbac.py" ]]; then
        echo "  + RBAC middleware exists"
    else
        echo "  x RBAC middleware not found"
        RBAC_OK=false
    fi

    RBAC_FE_FRAMEWORK="nuxt"
    [[ -f ".env" ]] && RBAC_FE_FRAMEWORK=$(grep -E "^FRONTEND_FRAMEWORK=" .env 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"' | tr -d "'" || echo "nuxt")
    [[ -z "$RBAC_FE_FRAMEWORK" ]] && RBAC_FE_FRAMEWORK="nuxt"

    if [[ "$RBAC_FE_FRAMEWORK" == "next" ]]; then
        if [[ -f "frontend/hooks/use-role.ts" ]] || [[ -f "frontend/hooks/useRole.ts" ]]; then
            echo "  + useRole hook exists"
        else
            echo "  x frontend/hooks/use-role.ts not found"
            RBAC_OK=false
        fi
    else
        if [[ -f "frontend/composables/useRole.ts" ]]; then
            echo "  + useRole composable exists"
        else
            echo "  x frontend/composables/useRole.ts not found"
            RBAC_OK=false
        fi
    fi

    if $RBAC_OK; then
        echo "  RBAC check: PASS"
        eval "STAGE_STATUS_rbac=PASS"
    else
        if [[ "$GATE_LEVEL" == "team" || "$GATE_LEVEL" == "production" ]]; then
            echo "  RBAC check: FAIL — required for $GATE_LEVEL gate"
            eval "STAGE_STATUS_rbac=FAIL"
            FAILED_STAGES+=("rbac")
        else
            echo "  RBAC check: WARNING — some RBAC files missing"
            eval "STAGE_STATUS_rbac=WARN"
        fi
    fi
    echo ""
fi

# ===========================================================
# Coverage Threshold Validation
# ===========================================================

# Read required coverage from deploy-gates.json
REQUIRED_LINE=0
REQUIRED_BRANCH=0
if command -v jq &>/dev/null; then
    REQUIRED_LINE=$(jq -r ".\"$GATE_LEVEL\".common.coverage.line // 0" "$DEPLOY_GATES" 2>/dev/null || echo "0")
    REQUIRED_BRANCH=$(jq -r ".\"$GATE_LEVEL\".common.coverage.branch // 0" "$DEPLOY_GATES" 2>/dev/null || echo "0")
fi

if [[ "$REQUIRED_LINE" -gt 0 ]]; then
    echo ""
    echo "Checking coverage thresholds (line: ${REQUIRED_LINE}%, branch: ${REQUIRED_BRANCH}%)..."

    # Backend coverage check
    if [[ -f ".claude/tmp/backend-coverage.json" ]] && command -v jq &>/dev/null; then
        ACTUAL_LINE=$(jq -r '.totals.percent_covered | floor' .claude/tmp/backend-coverage.json 2>/dev/null || echo "0")
        if [[ "$ACTUAL_LINE" -lt "$REQUIRED_LINE" ]]; then
            echo "  x Backend line coverage ${ACTUAL_LINE}% < required ${REQUIRED_LINE}%"
            FAILED_STAGES+=("coverage")
        else
            echo "  + Backend line coverage: ${ACTUAL_LINE}%"
        fi
    fi

    # Frontend coverage check
    if [[ -f "frontend/coverage/coverage-summary.json" ]] && command -v jq &>/dev/null; then
        FE_LINE=$(jq -r '.total.lines.pct | floor' frontend/coverage/coverage-summary.json 2>/dev/null || echo "0")
        FE_BRANCH=$(jq -r '.total.branches.pct | floor' frontend/coverage/coverage-summary.json 2>/dev/null || echo "0")
        COVERAGE_OK=true
        if [[ "$FE_LINE" -lt "$REQUIRED_LINE" ]]; then
            echo "  x Frontend line coverage ${FE_LINE}% < required ${REQUIRED_LINE}%"
            COVERAGE_OK=false
        fi
        if [[ "$FE_BRANCH" -lt "$REQUIRED_BRANCH" ]]; then
            echo "  x Frontend branch coverage ${FE_BRANCH}% < required ${REQUIRED_BRANCH}%"
            COVERAGE_OK=false
        fi
        if $COVERAGE_OK; then
            echo "  + Frontend coverage: ${FE_LINE}% line, ${FE_BRANCH}% branch"
        else
            FAILED_STAGES+=("coverage")
        fi
    fi
fi

# ===========================================================
# Gate Decision
# ===========================================================

if [[ ${#FAILED_STAGES[@]} -gt 0 ]]; then
    echo "==========================================================="
    echo " GATE: STAGES FAILED — ${FAILED_STAGES[*]}"
    echo "==========================================================="

    PIPELINE_END=$(date +%s)
    DURATION=$((PIPELINE_END - PIPELINE_START))

    cat > .claude/tmp/pipeline-results.md << RESULTS_EOF
Pipeline Results ($GATE_LEVEL gate / $DEPLOY_TARGET)
Timestamp: $TIMESTAMP | Duration: ${DURATION}s

Security:         ${STAGE_STATUS_security:-SKIP}
Smoke:            ${STAGE_STATUS_smoke:-SKIP}
Unit Tests:       ${STAGE_STATUS_unit:-SKIP}
Integration:      ${STAGE_STATUS_integration:-SKIP}
UI Tests:         ${STAGE_STATUS_ui:-SKIP}
Performance:      ${STAGE_STATUS_perf:-SKIP}
RBAC Check:       ${STAGE_STATUS_rbac:-SKIP}
Tier1 Ent.:       ${STAGE_STATUS_tier1:-SKIP}
Mobile:           ${STAGE_STATUS_mobile:-SKIP}
Coverage:         ${STAGE_STATUS_coverage:-SKIP}
Opus Review:      SKIPPED

GATE DECISION: PIPELINE FAILED
RESULTS_EOF

    cat .claude/tmp/pipeline-results.md
    exit 1
fi

# ===========================================================
# Stage: Opus Code Review (production gate only)
# ===========================================================

OPUS_STATUS="SKIP"
OPUS_EXIT=0

if stage_required "opus-review"; then
    echo "==========================================================="
    echo " ALL TESTS PASSED — Proceeding to Opus Code Review"
    echo "==========================================================="
    echo ""

    if ! bash .claude/scripts/build-review-payload.sh; then
        echo "ERROR: Failed to build review payload" >&2
        OPUS_STATUS="PAYLOAD_ERROR"
        OPUS_EXIT=1
    fi
    echo ""

    if [[ "$OPUS_STATUS" != "PAYLOAD_ERROR" ]]; then
        if command -v timeout &>/dev/null; then
            timeout 300 bash .claude/scripts/invoke-opus-reviewer.sh
        else
            bash .claude/scripts/invoke-opus-reviewer.sh
        fi
        OPUS_EXIT=$?

        OPUS_STATUS="APPROVED"
        [[ $OPUS_EXIT -ne 0 ]] && OPUS_STATUS="CHANGES REQUIRED"
    fi
fi

# ===========================================================
# Final Report
# ===========================================================

PIPELINE_END=$(date +%s)
DURATION=$((PIPELINE_END - PIPELINE_START))

OVERALL_DECISION="PIPELINE PASSED"
FINAL_EXIT=0
if [[ $OPUS_EXIT -ne 0 ]]; then
    OVERALL_DECISION="PIPELINE FAILED"
    FINAL_EXIT=1
fi

cat > .claude/tmp/pipeline-results.md << RESULTS_EOF
Pipeline Results ($GATE_LEVEL gate / $DEPLOY_TARGET)
Timestamp: $TIMESTAMP | Duration: ${DURATION}s

Security:         ${STAGE_STATUS_security:-SKIP}
Smoke:            ${STAGE_STATUS_smoke:-SKIP}
Unit Tests:       ${STAGE_STATUS_unit:-SKIP}
Integration:      ${STAGE_STATUS_integration:-SKIP}
UI Tests:         ${STAGE_STATUS_ui:-SKIP}
Performance:      ${STAGE_STATUS_perf:-SKIP}
RBAC Check:       ${STAGE_STATUS_rbac:-SKIP}
Tier1 Ent.:       ${STAGE_STATUS_tier1:-SKIP}
Mobile:           ${STAGE_STATUS_mobile:-SKIP}
Coverage:         ${STAGE_STATUS_coverage:-SKIP}
Opus Review:      $OPUS_STATUS

GATE DECISION: $OVERALL_DECISION
RESULTS_EOF

echo ""
cat .claude/tmp/pipeline-results.md

# ===========================================================
# Target-specific deployment (if pipeline passed)
# ===========================================================

if [[ $FINAL_EXIT -eq 0 ]]; then
    # Check if vercel deploy is enabled for this gate level
    VERCEL_ENABLED="false"
    if command -v jq &>/dev/null; then
        VERCEL_ENABLED=$(jq -r ".\"$GATE_LEVEL\".vercel.enabled // false" "$DEPLOY_GATES" 2>/dev/null || echo "false")
    fi

    if [[ "$VERCEL_ENABLED" == "true" ]]; then
        echo ""
        echo "==========================================================="
        echo " Pipeline passed — proceeding to cloud deployment"
        echo "==========================================================="
        echo ""
        CLOUD_ENV="${ENVIRONMENT:-staging}"
        if [[ -f ".claude/scripts/deploy-cloud.sh" ]]; then
            bash .claude/scripts/deploy-cloud.sh "$CLOUD_ENV" || {
                echo "WARNING: Cloud deployment failed." >&2
                FINAL_EXIT=1
            }
        else
            echo "WARNING: deploy-cloud.sh not found. Run scaffold-cloud-configs.sh first." >&2
        fi
    fi
fi

# ===========================================================
# Changelog Update (only on pipeline pass)
# ===========================================================

if [[ $FINAL_EXIT -eq 0 ]]; then
    echo ""
    if [[ -f ".claude/scripts/write-changelog-entry.sh" ]]; then
        bash .claude/scripts/write-changelog-entry.sh || {
            echo "WARNING: Changelog update failed (does not affect pipeline result)." >&2
        }
    fi
fi

exit $FINAL_EXIT
