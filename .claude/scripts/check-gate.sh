#!/usr/bin/env bash
set -uo pipefail

# Quick gate-readiness check without running the full pipeline
# Usage: bash .claude/scripts/check-gate.sh [mvp|team|production]
# Exit 0 = ready, Exit 1 = not ready

[[ "${AULENDIL_DEBUG:-}" == "1" ]] && set -x

GATE_LEVEL="${1:-mvp}"
DEPLOY_TARGET="${DEPLOY_TARGET:-vercel}"
BLOCKERS=()

echo "==========================================================="
echo " GATE READINESS CHECK — $GATE_LEVEL"
echo "==========================================================="
echo ""

# --- Check 1: Tests exist ---
if [[ -d "backend/tests" ]] || [[ -d "frontend/tests" ]]; then
    echo "  + Test directories exist"
else
    BLOCKERS+=("No test directories found (backend/tests or frontend/tests)")
fi

# --- Check 2: RBAC files (team and above) ---
if [[ "$GATE_LEVEL" == "team" || "$GATE_LEVEL" == "production" ]]; then
    RBAC_OK=true
    [[ ! -f "supabase/migrations/00000000000001_rbac.sql" ]] && RBAC_OK=false
    [[ ! -f "backend/middleware/rbac.py" ]] && [[ ! -f "backend/Middleware/RbacMiddleware.cs" ]] && RBAC_OK=false
    [[ ! -f "frontend/composables/useRole.ts" ]] && RBAC_OK=false

    if $RBAC_OK; then
        echo "  + RBAC files present"
    else
        BLOCKERS+=("RBAC files missing (migration, middleware, or useRole composable)")
    fi
fi

# --- Check 3: Health endpoint (team and above) ---
if [[ "$GATE_LEVEL" == "team" || "$GATE_LEVEL" == "production" ]]; then
    HEALTH_FOUND=false
    grep -rqlE '@(app|router)\.(get|route).*["\x27]/health["\x27]' backend/ 2>/dev/null && HEALTH_FOUND=true
    grep -rqlE 'MapGet.*"/health"' backend/ 2>/dev/null && HEALTH_FOUND=true

    if $HEALTH_FOUND; then
        echo "  + Health endpoint found"
    else
        BLOCKERS+=("No health endpoint (GET /health) found in backend/")
    fi
fi

# --- Check 4: RLS on migrations (production) ---
if [[ "$GATE_LEVEL" == "production" && -d "supabase/migrations" ]]; then
    RLS_MISSING=0
    for mig in supabase/migrations/*.sql; do
        [[ ! -f "$mig" ]] && continue
        if grep -qiE 'CREATE\s+TABLE' "$mig" 2>/dev/null; then
            if ! grep -qiE 'ENABLE\s+ROW\s+LEVEL\s+SECURITY|CREATE\s+POLICY' "$mig" 2>/dev/null; then
                RLS_MISSING=$((RLS_MISSING + 1))
            fi
        fi
    done
    if [[ $RLS_MISSING -eq 0 ]]; then
        echo "  + RLS enabled on all tables"
    else
        BLOCKERS+=("$RLS_MISSING migration(s) missing RLS policies")
    fi
fi

# --- Check 5: Schema isolation (Azure + production) ---
if [[ "$DEPLOY_TARGET" == "azure" && "$GATE_LEVEL" == "production" ]]; then
    if [[ -z "${APP_SCHEMA:-}" ]]; then
        BLOCKERS+=("APP_SCHEMA not set (required for Azure production)")
    else
        echo "  + APP_SCHEMA=$APP_SCHEMA"
    fi
fi

# --- Check 6: Docker (Azure) ---
if [[ "$DEPLOY_TARGET" == "azure" ]]; then
    if [[ -f "Dockerfile" ]]; then
        echo "  + Dockerfile exists"
    else
        BLOCKERS+=("Dockerfile missing (required for Azure deployment)")
    fi
fi

# --- Check 7: Lint/type-check ---
if command -v npx &>/dev/null && [[ -f "frontend/package.json" ]]; then
    if cd frontend && npx vue-tsc --noEmit 2>/dev/null; then
        echo "  + Frontend type check passes"
    else
        BLOCKERS+=("Frontend type check (vue-tsc) has errors")
    fi
    cd - &>/dev/null || true
fi

echo ""

# --- Result ---
if [[ ${#BLOCKERS[@]} -eq 0 ]]; then
    echo "==========================================================="
    echo " READY for $GATE_LEVEL gate"
    echo "==========================================================="
    exit 0
else
    echo "==========================================================="
    echo " NOT READY for $GATE_LEVEL — ${#BLOCKERS[@]} blocker(s):"
    echo "==========================================================="
    for b in "${BLOCKERS[@]}"; do
        echo "  x $b"
    done
    exit 1
fi
