#!/usr/bin/env bash
set -uo pipefail

# Create per-app PostgreSQL schema and dedicated role for Azure deployments
# Usage: bash .claude/scripts/setup-azure-db.sh <app-schema>
# Requires: psql, ADMIN_DATABASE_URL env var (admin connection string)
# Output: prints the app-scoped connection string to stdout
# Exit 0 = success, Exit 1 = failed

APP_SCHEMA="${1:-}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
AUDIT_LOG=".claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true

if [[ -z "$APP_SCHEMA" ]]; then
    echo "Usage: bash .claude/scripts/setup-azure-db.sh <app-schema>" >&2
    echo "Example: bash .claude/scripts/setup-azure-db.sh hr_leave_tracker" >&2
    exit 1
fi

# Validate schema name (alphanumeric + underscore only)
if ! echo "$APP_SCHEMA" | grep -qE '^[a-z][a-z0-9_]*$'; then
    echo "ERROR: app-schema must be lowercase alphanumeric + underscore (e.g. hr_leave_tracker)" >&2
    exit 1
fi

ROLE_NAME="${APP_SCHEMA}_owner"
echo "[$TIMESTAMP] setup-azure-db: schema=$APP_SCHEMA role=$ROLE_NAME" >> "$AUDIT_LOG"

echo "=========================================================="
echo " SETUP AZURE DATABASE"
echo " Schema: $APP_SCHEMA"
echo " Role:   $ROLE_NAME"
echo "=========================================================="
echo ""

# Check admin connection
ADMIN_DATABASE_URL="${ADMIN_DATABASE_URL:-}"
if [[ -z "$ADMIN_DATABASE_URL" ]]; then
    echo "ERROR: ADMIN_DATABASE_URL env var not set." >&2
    echo "  Set it to the admin/superuser PostgreSQL connection string." >&2
    exit 1
fi

if ! command -v psql &>/dev/null; then
    echo "ERROR: psql not found. Install postgresql-client." >&2
    exit 1
fi

# Generate random password for the app role
ROLE_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=\n' | head -c 24)

# ----------------------------------------------------------
# Execute schema setup as admin
# ----------------------------------------------------------
echo "Creating schema and role..."

# Generate SQL with validated values (schema name is alphanumeric-validated above)
SQL_TEMPLATE=$(cat << 'SQLTEMPLATE'
-- Create app-scoped role
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '__ROLE_NAME__') THEN
        CREATE ROLE __ROLE_NAME__ LOGIN PASSWORD '__ROLE_PASSWORD__';
        RAISE NOTICE 'Created role: __ROLE_NAME__';
    ELSE
        ALTER ROLE __ROLE_NAME__ PASSWORD '__ROLE_PASSWORD__';
        RAISE NOTICE 'Updated password for role: __ROLE_NAME__';
    END IF;
END $$;

-- Create app schema
CREATE SCHEMA IF NOT EXISTS __APP_SCHEMA__ AUTHORIZATION __ROLE_NAME__;

-- Grant usage on schema
GRANT USAGE ON SCHEMA __APP_SCHEMA__ TO __ROLE_NAME__;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA __APP_SCHEMA__ TO __ROLE_NAME__;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA __APP_SCHEMA__ TO __ROLE_NAME__;
ALTER DEFAULT PRIVILEGES IN SCHEMA __APP_SCHEMA__ GRANT ALL ON TABLES TO __ROLE_NAME__;
ALTER DEFAULT PRIVILEGES IN SCHEMA __APP_SCHEMA__ GRANT ALL ON SEQUENCES TO __ROLE_NAME__;

-- Set default search_path for role
ALTER ROLE __ROLE_NAME__ SET search_path = __APP_SCHEMA__;
SQLTEMPLATE
)

# Substitute validated values (ROLE_NAME and APP_SCHEMA are alphanumeric-validated;
# ROLE_PASSWORD is base64-filtered with no special SQL chars)
SQL_FINAL=$(echo "$SQL_TEMPLATE" \
    | sed "s/__ROLE_NAME__/${ROLE_NAME}/g" \
    | sed "s/__ROLE_PASSWORD__/${ROLE_PASSWORD}/g" \
    | sed "s/__APP_SCHEMA__/${APP_SCHEMA}/g")

echo "$SQL_FINAL" | psql "$ADMIN_DATABASE_URL"

if [[ $? -ne 0 ]]; then
    echo "ERROR: Schema setup failed." >&2
    exit 1
fi

echo "  + Schema '$APP_SCHEMA' created"
echo "  + Role '$ROLE_NAME' created with password"

# ----------------------------------------------------------
# Run migrations
# ----------------------------------------------------------
echo ""
echo "Running migrations..."
if command -v supabase &>/dev/null && [[ -d "supabase/migrations" ]]; then
    # Build app-scoped connection string
    DB_HOST=$(echo "$ADMIN_DATABASE_URL" | grep -oE '@[^:/]+' | tr -d '@')
    DB_PORT=$(echo "$ADMIN_DATABASE_URL" | grep -oE ':[0-9]+/' | tr -d ':/')
    DB_NAME=$(echo "$ADMIN_DATABASE_URL" | grep -oE '/[^?]+$' | tr -d '/')
    APP_DB_URL="postgresql://${ROLE_NAME}:${ROLE_PASSWORD}@${DB_HOST}:${DB_PORT:-5432}/${DB_NAME}?options=-csearch_path%3D${APP_SCHEMA}"

    psql "$APP_DB_URL" -f <(cat supabase/migrations/*.sql 2>/dev/null) 2>&1 | tee .claude/tmp/migration-output.txt || {
        echo "  WARNING: Some migrations failed. Check .claude/tmp/migration-output.txt"
    }
    echo "  + Migrations applied"
else
    echo "  - No supabase/migrations found — run migrations manually"
fi

# ----------------------------------------------------------
# Output connection string
# ----------------------------------------------------------
DB_HOST=$(echo "$ADMIN_DATABASE_URL" | grep -oE '@[^:/]+' | tr -d '@')
DB_PORT=$(echo "$ADMIN_DATABASE_URL" | grep -oE ':[0-9]+/' | tr -d ':/')
DB_NAME=$(echo "$ADMIN_DATABASE_URL" | grep -oE '/[^?]+$' | tr -d '/')
APP_DB_URL="postgresql://${ROLE_NAME}:${ROLE_PASSWORD}@${DB_HOST}:${DB_PORT:-5432}/${DB_NAME}?options=-csearch_path%3D${APP_SCHEMA}"

echo ""
echo "=========================================================="
echo " DATABASE READY"
echo "=========================================================="
echo ""
echo "Add to .env.azure:"
echo "  DATABASE_URL=$APP_DB_URL"
echo ""
echo "IMPORTANT: Save the connection string — the password cannot be retrieved later."

echo "[$TIMESTAMP] setup-azure-db: completed schema=$APP_SCHEMA" >> "$AUDIT_LOG"
exit 0
