#!/usr/bin/env bash
set -uo pipefail

# Master CI/CD pipeline orchestrator — gate-level and deploy-target aware
# Usage: bash .claude/scripts/run-pipeline.sh [mvp|team|production]
# Env:   DEPLOY_TARGET=vercel|azure  (defaults to vercel if unset)
# Reads .claude/deploy-gates.json for stage requirements per gate level
# Exit 0 = PIPELINE PASSED, Exit 1 = PIPELINE FAILED

GATE_LEVEL="${1:-production}"
DEPLOY_TARGET="${DEPLOY_TARGET:-vercel}"
PIPELINE_START=$(date +%s)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Set deploy mode, restore build mode on exit
echo "deploy" > .claude/mode
trap 'echo "build" > .claude/mode' EXIT

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
    grep -q "\"$stage\"" <<< "$gate_block"
}

# Track stage results
declare -a FAILED_STAGES=()
declare -A STAGE_STATUS=()
declare -A STAGE_PIDS=()

# ===========================================================
# Stage: Security Scan (always runs)
# ===========================================================
echo "Running security scan..."
(
    bash .claude/scripts/security-scan.sh > .claude/tmp/security-output.txt 2>&1
) &
STAGE_PIDS[security]=$!

# ===========================================================
# Stage: Smoke Test (mvp and above)
# ===========================================================
if stage_required "app-starts" || stage_required "happy-path-works"; then
    echo "Running smoke tests..."
    (
        GATE_LEVEL="$GATE_LEVEL" bash .claude/scripts/smoke-test.sh > .claude/tmp/smoke-output.txt 2>&1
    ) &
    STAGE_PIDS[smoke]=$!
else
    STAGE_STATUS[smoke]="SKIP"
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
    STAGE_PIDS[unit]=$!
else
    STAGE_STATUS[unit]="SKIP"
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
    STAGE_PIDS[integration]=$!
else
    STAGE_STATUS[integration]="SKIP"
fi

# ===========================================================
# Stage: UI Tests (team and above)
# ===========================================================
if stage_required "ui-tests"; then
    echo "Running UI tests..."
    (
        if command -v npx &>/dev/null && [[ -f "frontend/playwright.config.ts" || -f "frontend/playwright.config.js" ]]; then
            HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
            if [[ "$HTTP_STATUS" == "000" || "$HTTP_STATUS" == "0" ]]; then
                echo '{"stage": "ui-tests", "overall_status": "SKIP", "reason": "App not running"}' > .claude/tmp/ui-results.json
                exit 0
            fi
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
    STAGE_PIDS[ui]=$!
else
    STAGE_STATUS[ui]="SKIP"
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

        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
        if [[ "$HTTP_STATUS" != "000" && "$HTTP_STATUS" != "0" ]]; then
            if npx --yes @lhci/cli --version &>/dev/null 2>&1; then
                npx --yes @lhci/cli collect --url=http://localhost:3000 --numberOfRuns=1 \
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
    STAGE_PIDS[perf]=$!
else
    STAGE_STATUS[perf]="SKIP"
fi

# ===========================================================
# Azure-specific: Schema isolation check
# ===========================================================
if [[ "$DEPLOY_TARGET" == "azure" ]] && stage_required "schema-isolation-check"; then
    echo "Running Azure schema isolation check..."
    (
        APP_SCHEMA="${APP_SCHEMA:-}"
        ISSUES=0

        if [[ -z "$APP_SCHEMA" ]]; then
            echo "  WARNING: APP_SCHEMA not set — schema isolation cannot be verified"
            ISSUES=$((ISSUES + 1))
        fi

        # Check migrations don't reference a hardcoded schema name
        if [[ -d "supabase/migrations" && -n "$APP_SCHEMA" ]]; then
            OTHER_SCHEMAS=$(grep -rE '\bSET\s+search_path\s+TO\s+' supabase/migrations/ 2>/dev/null \
                | grep -v "$APP_SCHEMA" | grep -v "public" | head -5 || true)
            if [[ -n "$OTHER_SCHEMAS" ]]; then
                echo "  WARNING: Migrations reference schemas other than $APP_SCHEMA"
                echo "$OTHER_SCHEMAS"
                ISSUES=$((ISSUES + 1))
            fi
        fi

        if [[ -n "$BLOB_CONTAINER" && "$BLOB_CONTAINER" == "$APP_SCHEMA" ]]; then
            echo "  + BLOB_CONTAINER matches APP_SCHEMA: $BLOB_CONTAINER"
        fi

        if [[ $ISSUES -eq 0 ]]; then
            echo '{"stage": "schema-isolation-check", "overall_status": "PASS"}' > .claude/tmp/schema-check-results.json
            exit 0
        else
            echo '{"stage": "schema-isolation-check", "overall_status": "WARN", "issues": '"$ISSUES"'}' \
                > .claude/tmp/schema-check-results.json
            exit 0  # Warn only, don't fail pipeline
        fi
    ) &
    STAGE_PIDS[schema]=$!
else
    STAGE_STATUS[schema]="SKIP"
fi

# ===========================================================
# Azure-specific: Docker build
# ===========================================================
if [[ "$DEPLOY_TARGET" == "azure" ]] && stage_required "docker-build"; then
    echo "Running Docker build check..."
    (
        if [[ ! -f "Dockerfile" ]]; then
            echo "  WARNING: Dockerfile not found — run scaffold-azure-configs.sh first"
            echo '{"stage": "docker-build", "overall_status": "SKIP", "reason": "No Dockerfile"}' \
                > .claude/tmp/docker-build-results.json
            exit 0
        fi
        if ! command -v docker &>/dev/null; then
            echo "  WARNING: Docker not available — skipping build check"
            echo '{"stage": "docker-build", "overall_status": "SKIP", "reason": "Docker not found"}' \
                > .claude/tmp/docker-build-results.json
            exit 0
        fi
        docker build -t pipeline-check:latest . > .claude/tmp/docker-build.log 2>&1
        if [[ $? -eq 0 ]]; then
            docker rmi pipeline-check:latest &>/dev/null || true
            echo '{"stage": "docker-build", "overall_status": "PASS"}' > .claude/tmp/docker-build-results.json
            exit 0
        else
            echo '{"stage": "docker-build", "overall_status": "FAIL"}' > .claude/tmp/docker-build-results.json
            exit 1
        fi
    ) &
    STAGE_PIDS[docker]=$!
else
    STAGE_STATUS[docker]="SKIP"
fi

# ===========================================================
# Wait for all stages
# ===========================================================
echo ""
echo "Waiting for stages to complete..."
echo ""

for stage in security smoke unit integration ui perf schema docker; do
    if [[ -n "${STAGE_PIDS[$stage]+x}" ]]; then
        wait "${STAGE_PIDS[$stage]}" 2>/dev/null
        EXIT_CODE=$?
        if [[ $EXIT_CODE -eq 0 ]]; then
            STAGE_STATUS[$stage]="PASS"
            echo "  + $stage: PASS"
        else
            STAGE_STATUS[$stage]="FAIL"
            FAILED_STAGES+=("$stage")
            echo "  x $stage: FAIL (exit $EXIT_CODE)"
        fi
    else
        echo "  - $stage: ${STAGE_STATUS[$stage]:-SKIP}"
    fi
done

echo ""

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

Security:         ${STAGE_STATUS[security]:-SKIP}
Smoke:            ${STAGE_STATUS[smoke]:-SKIP}
Unit Tests:       ${STAGE_STATUS[unit]:-SKIP}
Integration:      ${STAGE_STATUS[integration]:-SKIP}
UI Tests:         ${STAGE_STATUS[ui]:-SKIP}
Performance:      ${STAGE_STATUS[perf]:-SKIP}
Schema Check:     ${STAGE_STATUS[schema]:-SKIP}
Docker Build:     ${STAGE_STATUS[docker]:-SKIP}
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

    bash .claude/scripts/build-review-payload.sh
    echo ""

    timeout 300 bash .claude/scripts/invoke-opus-reviewer.sh
    OPUS_EXIT=$?

    OPUS_STATUS="APPROVED"
    [[ $OPUS_EXIT -ne 0 ]] && OPUS_STATUS="CHANGES REQUIRED"
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

Security:         ${STAGE_STATUS[security]:-SKIP}
Smoke:            ${STAGE_STATUS[smoke]:-SKIP}
Unit Tests:       ${STAGE_STATUS[unit]:-SKIP}
Integration:      ${STAGE_STATUS[integration]:-SKIP}
UI Tests:         ${STAGE_STATUS[ui]:-SKIP}
Performance:      ${STAGE_STATUS[perf]:-SKIP}
Schema Check:     ${STAGE_STATUS[schema]:-SKIP}
Docker Build:     ${STAGE_STATUS[docker]:-SKIP}
Opus Review:      $OPUS_STATUS

GATE DECISION: $OVERALL_DECISION
RESULTS_EOF

echo ""
cat .claude/tmp/pipeline-results.md

# ===========================================================
# RBAC Verification (team and above)
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
        echo "  x backend/middleware/rbac.py not found"
        RBAC_OK=false
    fi

    if [[ -f "frontend/composables/useRole.ts" ]]; then
        echo "  + useRole composable exists"
    else
        echo "  x frontend/composables/useRole.ts not found"
        RBAC_OK=false
    fi

    if $RBAC_OK; then
        echo "  RBAC check: PASS"
    else
        echo "  RBAC check: WARNING — some RBAC files missing"
    fi
    echo ""
fi

# ===========================================================
# Target-specific deployment (if pipeline passed)
# ===========================================================

if [[ $FINAL_EXIT -eq 0 ]]; then
    if [[ "$DEPLOY_TARGET" == "azure" ]]; then
        # Check if azure deploy is enabled for this gate level
        AZURE_ENABLED="false"
        if command -v jq &>/dev/null; then
            AZURE_ENABLED=$(jq -r ".\"$GATE_LEVEL\".azure.enabled // false" "$DEPLOY_GATES" 2>/dev/null || echo "false")
        fi

        if [[ "$AZURE_ENABLED" == "true" ]]; then
            echo ""
            echo "==========================================================="
            echo " Pipeline passed — proceeding to Azure deployment"
            echo "==========================================================="
            echo ""
            CLOUD_ENV="${ENVIRONMENT:-staging}"
            if [[ -f ".claude/scripts/deploy-azure.sh" ]]; then
                bash .claude/scripts/deploy-azure.sh "$CLOUD_ENV" || {
                    echo "WARNING: Azure deployment failed." >&2
                    FINAL_EXIT=1
                }
            else
                echo "WARNING: deploy-azure.sh not found. Run scaffold-azure-configs.sh first." >&2
            fi
        fi

    elif [[ "$DEPLOY_TARGET" == "cloud" || "$DEPLOY_TARGET" == "vercel" ]]; then
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
