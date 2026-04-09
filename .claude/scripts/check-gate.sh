#!/usr/bin/env bash
set -uo pipefail

# Quick gate-readiness check without running the full pipeline
# Usage: bash .claude/scripts/check-gate.sh [mvp|team|production]
# Exit 0 = ready, Exit 1 = not ready

[[ "${AULENDIL_DEBUG:-}" == "1" ]] && set -x

GATE_LEVEL="${1:-mvp}"
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
    [[ ! -f "backend/middleware/rbac.py" ]] && RBAC_OK=false

    CG_FE_FRAMEWORK="nuxt"
    [[ -f ".env" ]] && CG_FE_FRAMEWORK=$(grep -E "^FRONTEND_FRAMEWORK=" .env 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"' | tr -d "'" || echo "nuxt")
    [[ -z "$CG_FE_FRAMEWORK" ]] && CG_FE_FRAMEWORK="nuxt"

    if [[ "$CG_FE_FRAMEWORK" == "next" ]]; then
        [[ ! -f "frontend/hooks/use-role.ts" ]] && [[ ! -f "frontend/hooks/useRole.ts" ]] && RBAC_OK=false
    else
        [[ ! -f "frontend/composables/useRole.ts" ]] && RBAC_OK=false
    fi

    if $RBAC_OK; then
        echo "  + RBAC files present"
    else
        BLOCKERS+=("RBAC files missing (migration, middleware, or useRole composable/hook)")
    fi
fi

# --- Check 3: Health endpoint (team and above) ---
if [[ "$GATE_LEVEL" == "team" || "$GATE_LEVEL" == "production" ]]; then
    HEALTH_FOUND=false
    grep -rqlE '@(app|router)\.(get|route).*["\x27]/health["\x27]' backend/ 2>/dev/null && HEALTH_FOUND=true

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

# --- Check 5: Lint/type-check (framework-aware) ---
if command -v npx &>/dev/null && [[ -f "frontend/package.json" ]]; then
    if [[ "${CG_FE_FRAMEWORK:-nuxt}" == "next" ]]; then
        if cd frontend && npx tsc --noEmit 2>/dev/null; then
            echo "  + Frontend type check passes"
        else
            BLOCKERS+=("Frontend type check (tsc) has errors")
        fi
    else
        if cd frontend && npx vue-tsc --noEmit 2>/dev/null; then
            echo "  + Frontend type check passes"
        else
            BLOCKERS+=("Frontend type check (vue-tsc) has errors")
        fi
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
