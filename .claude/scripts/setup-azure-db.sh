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

psql "$ADMIN_DATABASE_URL" << SQL
-- Create app-scoped role
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${ROLE_NAME}') THEN
        CREATE ROLE ${ROLE_NAME} LOGIN PASSWORD '${ROLE_PASSWORD}';
        RAISE NOTICE 'Created role: ${ROLE_NAME}';
    ELSE
        ALTER ROLE ${ROLE_NAME} PASSWORD '${ROLE_PASSWORD}';
        RAISE NOTICE 'Updated password for role: ${ROLE_NAME}';
    END IF;
END \$\$;

-- Create app schema
CREATE SCHEMA IF NOT EXISTS ${APP_SCHEMA} AUTHORIZATION ${ROLE_NAME};

-- Grant usage on schema
GRANT USAGE ON SCHEMA ${APP_SCHEMA} TO ${ROLE_NAME};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA ${APP_SCHEMA} TO ${ROLE_NAME};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA ${APP_SCHEMA} TO ${ROLE_NAME};
ALTER DEFAULT PRIVILEGES IN SCHEMA ${APP_SCHEMA} GRANT ALL ON TABLES TO ${ROLE_NAME};
ALTER DEFAULT PRIVILEGES IN SCHEMA ${APP_SCHEMA} GRANT ALL ON SEQUENCES TO ${ROLE_NAME};

-- Set default search_path for role
ALTER ROLE ${ROLE_NAME} SET search_path = ${APP_SCHEMA};
SQL

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
