# Tech Stack Reference

This file is the single source of truth for all technology decisions.
Claude Code reads this file to determine which tools to install, which
linters to run, which test frameworks to invoke, and which conventions
to enforce. Edit this file to change the stack — do not change individual
hook scripts or agent files directly.

---

## Runtime

RUNTIME: python
VERSION: 3.9+  # Use whatever version is installed; minimum 3.9
PACKAGE_MANAGER: pip
LOCKFILE: requirements.txt
VIRTUAL_ENV: .venv

---

## Frontend

FRAMEWORK: vue
META_FRAMEWORK: nuxt
VERSION: Nuxt 3 / Vue 3
LANGUAGE: typescript
STYLING: tailwindcss
COMPONENT_STYLE: composition-api
STATE_MANAGEMENT: pinia
FORM_VALIDATION: vee-validate + zod

---

## Backend

FRAMEWORK: fastapi
LANGUAGE: python
API_STYLE: REST
ASYNC: true
AUTH: supabase-auth
FILE_UPLOADS: supabase-storage

---

## Database

PROVIDER: supabase
ENGINE: postgresql
ORM: supabase-py (postgrest client)
MIGRATIONS: supabase-cli
REALTIME: supabase-realtime
RLS: true  # Row Level Security enforced on all tables

---

## Testing

### Backend
UNIT: pytest
COVERAGE: pytest-cov
SECURITY: bandit
TYPE_CHECK: mypy
LINT: ruff

### Frontend
UNIT: vitest
COMPONENT: @vue/test-utils
E2E: playwright
VISUAL_REGRESSION: playwright-screenshots

### Integration
FRAMEWORK: pytest (httpx AsyncClient against FastAPI)
DB_STRATEGY: supabase test project (separate project per env)

### Performance
API: k6
FRONTEND: lighthouse-ci

---

## Code Quality

### Python
LINTER: ruff
FORMATTER: ruff format
TYPE_CHECKER: mypy
SECURITY: bandit
MIN_COVERAGE_LINES: 80
MIN_COVERAGE_BRANCHES: 70

### TypeScript / Vue
LINTER: eslint
FORMATTER: prettier
TYPE_CHECKER: vue-tsc
MIN_COVERAGE_LINES: 80
MIN_COVERAGE_BRANCHES: 70

---

## Infrastructure

| | Cloud (Vercel) | Company Server (Azure) |
|---|---|---|
| **Frontend** | Vercel SSR (Nuxt 3 with edge middleware) | Azure Container Apps (Docker container) |
| **Backend** | Vercel serverless (FastAPI as Python functions at /api/*) | Azure Container Apps (FastAPI in same container) |
| **Database** | Supabase Cloud (PostgreSQL + Auth + Storage + Realtime) | Supabase Cloud or Azure Database for PostgreSQL (shared server, per-app schema via `APP_SCHEMA`) |
| **Secrets** | `.env.local` (local), Vercel env vars + Supabase Vault (production) | `.env.local` (local), Azure Key Vault / Container App secrets (production) |
| **Auth** | Supabase Auth (email/password, OAuth, JWT) | OAuth2 Proxy → Google SSO → `X-Forwarded-Email` header |
| **Storage** | Supabase Storage (bucket RLS, signed URLs < 1hr) | Azure Blob Storage (per-app container via `BLOB_CONTAINER`, RBAC-scoped) |
| **CI/CD** | Claude Code pipeline + Vercel deploy | Claude Code pipeline + Docker build/push/deploy stages |

DEPLOY_TARGET: vercel  # or "azure" — set in .env at scaffold time, defaults to vercel if unset
SECRETS_LOCAL: .env.local
CI_CD: claude-code pipeline (this system)

---

## Project Conventions

DIRECTORY_STRUCTURE: |
  /
  ├── frontend/               # Nuxt 3 application
  │   ├── components/         # Vue components (use design system)
  │   ├── composables/        # Shared Vue composables
  │   ├── pages/              # Nuxt file-based routing
  │   ├── stores/             # Pinia stores
  │   ├── services/           # All Supabase client calls go here
  │   ├── types/              # Shared TypeScript types
  │   └── tests/              # Vitest unit + Playwright e2e
  ├── backend/                # FastAPI application
  │   ├── routes/             # FastAPI routers (no business logic)
  │   ├── services/           # Business logic layer
  │   ├── models/             # Pydantic models
  │   ├── middleware/         # Auth, logging, error handling
  │   └── tests/              # pytest suites
  ├── supabase/               # Supabase project config
  │   ├── migrations/         # SQL migration files (supabase db diff)
  │   ├── functions/          # Edge Functions (Deno)
  │   └── seed.sql            # Development seed data
  └── docs/                   # Reference docs (this file lives here)

API_BASE_URL_ENV: SUPABASE_URL
API_KEY_ENV: SUPABASE_ANON_KEY
SERVICE_KEY_ENV: SUPABASE_SERVICE_ROLE_KEY

---

## Bootstrap

BOOTSTRAP: bash scripts/bootstrap.sh
BOOTSTRAP_DESCRIPTION: |
  One command to go from empty project to running app.
  Scaffolds Nuxt 3 frontend + FastAPI backend + Supabase local,
  installs all dependencies and dev tools, starts all services.
  After bootstrap: frontend at localhost:3000, backend at localhost:8000,
  Supabase Studio at localhost:54323.
  Replaces the previous init.sh (which only installed tools).

---

## Run Commands

DEV_FRONTEND: cd frontend && npm run dev
DEV_BACKEND: cd backend && uvicorn main:app --reload
TEST_BACKEND: cd backend && pytest --cov --cov-report=term-missing
TEST_FRONTEND: cd frontend && npm run test
TEST_E2E: cd frontend && npx playwright test
LINT_BACKEND: cd backend && ruff check . && mypy .
LINT_FRONTEND: cd frontend && npm run lint
MIGRATE: supabase db push
MIGRATE_NEW: supabase db diff -f [migration_name]
TYPE_CHECK_FRONTEND: cd frontend && vue-tsc --noEmit

---

## Supabase-Specific Conventions

RLS_REQUIRED: true   # Every table must have RLS policies defined
AUTH_PATTERN: |
  - Use supabase.auth.getUser() server-side to verify sessions
  - Never trust client-supplied user IDs — always derive from JWT
  - Service role key only in backend, never in frontend
REALTIME_PATTERN: |
  - Use Supabase Realtime channels for live updates
  - Subscribe in Vue composables, unsubscribe in onUnmounted
STORAGE_PATTERN: |
  - All file uploads through Supabase Storage
  - Bucket policies must restrict access via RLS
  - Never expose signed URLs longer than 1 hour

---

## What to Enforce Automatically

The following must be caught by hooks and agents — they are
non-negotiable for this stack:

BLOCK_ON:
  - SUPABASE_SERVICE_ROLE_KEY referenced in any frontend file
  - Direct Supabase client calls inside Vue components (must go via /services/)
  - Raw SQL strings in Python (use supabase-py query builder)
  - Missing RLS policy when a new table migration is detected
  - Pinia store mutated directly from a component (must use actions)
  - API calls in Pinia getters (getters must be pure computed values)
  - Passwords or tokens in any file tracked by git
  - pytest tests without the @pytest.mark.asyncio decorator on async tests

WARN_ON:
  - Vue component over 200 lines (should be split)
  - Pinia store over 150 lines (should be split by domain)
  - FastAPI route handler over 20 lines (logic belongs in service layer)
  - Any TODO/FIXME left in changed files

---

## Enterprise Feature Implementation Patterns

AUTH_STACK: |
  - supabase.auth for email/password, Google OAuth, MFA (TOTP via
    Supabase Auth MFA APIs: mfa.enroll(), mfa.challenge(), mfa.verify())
  - Row Level Security as the ABAC enforcement layer
  - Custom claims in JWT for role (Admin/Manager/Member/Viewer) via
    Supabase Auth hook or custom claims function
  - slowapi for rate limiting in FastAPI (@limiter.limit("10/minute"))
  - Invite flow: generate signed token, store in invitations table,
    validate on registration, assign role from invite
  - Account lockout: login_attempts counter in profiles table,
    check before auth, reset on success, lock after 5 failures

NOTIFICATIONS_STACK: |
  - In-app: notifications table in Supabase + Realtime channel subscription
    via useNotifications() composable in frontend
  - Email: Resend (resend.com) via FastAPI background tasks
    (from resend import Resend; client.emails.send())
  - Push: Web Push API with VAPID keys, push_subscriptions table,
    service worker push handler in frontend
  - Preferences: notification_preferences table
    (user_id, channel, event_type, enabled)
  - Digest: cron job aggregating unread notifications,
    user preference for digest frequency

OBSERVABILITY_STACK: |
  - Structured logging: Python structlog library configured with
    JSONRenderer → stdout → log drain or external aggregator
  - Correlation ID: FastAPI middleware generates uuid4, attaches to
    request state, included in every log entry and response meta
  - Error tracking: sentry-sdk for Python FastAPI integration,
    @sentry/vue for frontend, DSN stored in env vars
  - Audit log: audit_log table with DB triggers on sensitive tables,
    immutable (RLS: no UPDATE or DELETE policies)
  - Health: FastAPI /health route pinging Supabase DB, Auth, Storage
  - Performance: FastAPI middleware recording request duration,
    Sentry performance monitoring or custom p50/p95/p99 metrics

COMPLIANCE_STACK: |
  - Data export: FastAPI background task generating CSV/JSON per user,
    delivered via signed Supabase Storage URL (max 1 hour)
  - Soft deletes: deleted_at timestamptz column on all user-facing tables,
    all queries filtered by deleted_at IS NULL
  - Consent: terms_acceptances table
    (user_id, version, accepted_at, ip_address)
  - Erasure: stored procedure that anonymizes PII in place
    (name → 'REDACTED', email → hash@redacted.com),
    erasure_requests table tracking workflow status
  - Retention: retention_policies config table,
    cron job purging data past configurable retention period

FEATURE_FLAGS_STACK: |
  - feature_flags table: (key, enabled, allowed_roles jsonb[],
    allowed_users uuid[], description, updated_at)
  - FastAPI dependency injection: Depends(require_flag("feature_name"))
    checks flag table, returns 404 if disabled for user's role
  - Vue composable: useFeatureFlag(key) reads from Pinia featureFlags store
  - Pinia store: hydrated at app init from GET /api/feature-flags
    (returns only flags enabled for current user's role)
  - Admin UI: feature flag management page for Admin role

SECURITY_HEADERS_STACK: |
  - HSTS: Strict-Transport-Security: max-age=31536000; includeSubDomains
    (set in Vercel config or Nuxt server middleware)
  - CSP: Content-Security-Policy header configured in Nuxt security module
    or custom server middleware (default-src 'self', script-src 'self',
    no unsafe-inline except where explicitly needed)
  - CORS: FastAPI CORSMiddleware with allow_origins set to explicit
    production domain(s), never wildcard '*'
  - X-Content-Type-Options: nosniff
  - X-Frame-Options: DENY
  - Referrer-Policy: strict-origin-when-cross-origin

---

## Access Patterns

DEFAULT_PATTERN: internal-only
SUPPORTED_PATTERNS:
  - internal-only: All users authenticate via company SSO or Supabase Auth email/password
  - dual-portal: Internal users via SSO (/app/*) + external users via invite-only (/portal/*)

EXTERNAL_ACCESS_RULES: |
  When external access is needed:
  - Create separate RLS policies scoped to organization_id or tenant_id
  - External users get a dedicated role: 'external_viewer' or 'external_user'
  - External-facing routes must have stricter rate limiting (5/minute vs 10/minute)
  - Invite-only registration for external users (no self-signup)
  - External portal uses a separate Nuxt layout with restricted navigation
  - All external-facing data queries must include organization scope filter

EXTERNAL_SUPABASE_TABLES: |
  When dual-portal pattern is active, add:
  - organizations (id uuid, name text, domain text, created_at, updated_at, deleted_at)
  - organization_members (user_id uuid, org_id uuid, role text, invited_by uuid, created_at)
  External RLS policies: auth.uid() IN (SELECT user_id FROM organization_members WHERE org_id = record.org_id)

---

TIER1_SUPABASE_TABLES_REQUIRED: |
  Every app must have these tables at minimum:
  - users (managed by Supabase Auth, extended via profiles table)
  - profiles (id references auth.users, display_name, avatar_url,
    login_attempts, locked_until, created_at, updated_at, deleted_at)
  - roles (id uuid, name text UNIQUE, permissions jsonb, created_at)
  - user_roles (user_id uuid, role_id uuid, assigned_by uuid,
    created_at) with UNIQUE(user_id, role_id)
  - invitations (id uuid, email text, role_id uuid, token text UNIQUE,
    invited_by uuid, expires_at timestamptz, accepted_at timestamptz,
    created_at)
  All tables must have RLS enabled with appropriate policies.

TIER2_SUPABASE_TABLES_REQUIRED: |
  Must exist before production:
  - notifications (id uuid, user_id uuid, type text, title text,
    body text, read_at timestamptz, created_at timestamptz)
  - notification_preferences (user_id uuid, channel text,
    event_type text, enabled boolean, PRIMARY KEY(user_id, channel, event_type))
  - audit_log (id uuid, user_id uuid, action text, table_name text,
    record_id uuid, old_val jsonb, new_val jsonb, ip_address inet,
    created_at timestamptz) — RLS: SELECT only for admins, no UPDATE/DELETE
  - feature_flags (key text PRIMARY KEY, enabled boolean,
    allowed_roles jsonb, allowed_users jsonb,
    description text, updated_at timestamptz)
  - terms_acceptances (user_id uuid, version text, accepted_at timestamptz,
    ip_address inet, PRIMARY KEY(user_id, version))
  - feedback (id uuid, user_id uuid, page text, message text,
    created_at timestamptz)
  - erasure_requests (id uuid, user_id uuid, status text,
    requested_at timestamptz, completed_at timestamptz)
