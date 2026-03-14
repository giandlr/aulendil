---
globs: ["backend/**/*.py", "supabase/migrations/**/*.sql", "docker-compose.azure.yml", ".env.azure.template"]
---

# App Isolation (Azure)

These rules apply when `DEPLOY_TARGET=azure`. Each app gets dedicated schema and storage isolation on shared infrastructure.

## Schema Isolation

- Every app has its own PostgreSQL schema: `APP_SCHEMA=<app_name>` (e.g. `hr_leave_tracker`)
- The value is derived from the app name at scaffold time — never hardcoded
- All table names in migrations must be prefixed with `SET search_path TO APP_SCHEMA` or use fully-qualified `schema.table` references
- A dedicated database role (`<app_schema>_owner`) owns all objects in the schema — the app connects as this role
- No cross-schema queries — apps must not reference other schemas
- `setup-azure-db.sh <app-schema>` creates the schema, role, and restricted connection string

## Storage Isolation

- Every app has its own Blob Storage container: `BLOB_CONTAINER=<app_name>`
- Default is one container per app — opt-in sharing requires explicit IT approval
- Never hard-code the container name; always read from `BLOB_CONTAINER` env var
- Access uses app-scoped RBAC credentials, not storage account keys

## Scope Note

These isolation rules apply to Azure deployments only. When `DEPLOY_TARGET=vercel`, Supabase handles isolation via RLS policies and the standard `auth.uid()` scoping — no schema separation needed.

## What to Enforce

BLOCK (Azure mode only):
- Migrations that reference a schema name other than the `APP_SCHEMA` value
- Direct Blob Storage access using the storage account key (must use app-scoped credentials)
- Cross-schema SQL queries (SELECT from another schema)

WARN:
- Container name or schema name hardcoded as a string literal (should read from env var)
