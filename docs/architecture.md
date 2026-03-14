# Architecture

## System Overview

This application uses a decoupled frontend/backend architecture with Supabase as the backend-as-a-service platform providing database, authentication, storage, and realtime capabilities.

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────────┐
│   Nuxt 3 App    │────▶│   FastAPI API    │────▶│     Supabase        │
│   (Vercel)      │     │   (Edge/Server)  │     │  ┌───────────────┐  │
│                 │     │                  │     │  │  PostgreSQL    │  │
│  Vue 3 + TS     │     │  Python 3.9+     │     │  │  + RLS        │  │
│  Pinia stores   │     │  Pydantic models │     │  ├───────────────┤  │
│  TailwindCSS    │     │  Async handlers  │     │  │  Auth (JWT)   │  │
│                 │     │                  │     │  ├───────────────┤  │
│  Supabase JS ──────────────────────────────────▶  │  Storage      │  │
│  (anon key)     │     │                  │     │  ├───────────────┤  │
│                 │     │                  │     │  │  Realtime      │  │
└─────────────────┘     └─────────────────┘     │  └───────────────┘  │
                                                 └─────────────────────┘
```

## Technology Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Frontend framework | Nuxt 3 / Vue 3 | File-based routing, SSR support, excellent DX, composition API |
| State management | Pinia | Official Vue state manager, TypeScript native, devtools support |
| Styling | TailwindCSS | Utility-first, no context switching, consistent design system |
| Backend framework | FastAPI | Async native, auto-generated OpenAPI docs, Pydantic validation |
| Database | Supabase (PostgreSQL) | Managed PostgreSQL with RLS, Auth, Storage, Realtime built-in |
| Auth | Supabase Auth | JWT-based, handles refresh tokens, social login, email/password |
| Frontend hosting | Vercel | Zero-config Nuxt deployment, edge functions, preview deploys |
| CI/CD | Claude Code pipeline | AI-powered testing, code review, and quality enforcement |

## Key Data Flows

### Authentication Flow
1. User submits credentials → Supabase Auth
2. Supabase returns JWT access token + refresh token
3. Frontend stores session via Supabase client
4. All API requests include JWT in Authorization header
5. Backend verifies JWT via `supabase.auth.getUser()`
6. RLS policies enforce row-level access in database

### API Request Flow
1. Vue component calls service function (never Supabase directly)
2. Service makes request to FastAPI endpoint
3. FastAPI middleware: verify JWT → attach user → log request with correlation ID
4. Route handler delegates to service layer
5. Service uses supabase-py query builder (RLS enforced)
6. Response wrapped in standard envelope with correlation ID

### Realtime Flow
1. Vue composable subscribes to Supabase Realtime channel
2. Supabase pushes changes via WebSocket (RLS enforced)
3. Composable updates Pinia store
4. Components reactively re-render

## External Dependencies

| Dependency | Purpose | Environment Variable |
|-----------|---------|---------------------|
| Supabase | Database, Auth, Storage, Realtime | `SUPABASE_URL`, `SUPABASE_ANON_KEY` |
| Supabase (server) | Admin operations | `SUPABASE_SERVICE_ROLE_KEY` (backend only) |
| Vercel | Frontend hosting | Configured via Vercel dashboard |

## Environment Variables

| Variable | Where | Description |
|----------|-------|-------------|
| `SUPABASE_URL` | Frontend + Backend | Supabase project URL |
| `SUPABASE_ANON_KEY` | Frontend + Backend | Public API key (respects RLS) |
| `SUPABASE_SERVICE_ROLE_KEY` | Backend ONLY | Admin key (bypasses RLS) |
| `SUPABASE_JWT_SECRET` | Backend | For manual JWT verification if needed |

**Security:** `SUPABASE_SERVICE_ROLE_KEY` must NEVER appear in frontend code or be exposed to the client.

## Local Development Setup

```bash
# 1. Clone and install
git clone <repo> && cd <project>
bash scripts/bootstrap.sh

# 2. Set up Supabase
supabase start                    # Local Supabase instance
cp .env.example .env.local       # Copy and fill in environment variables

# 3. Run migrations
supabase db push

# 4. Start development servers
cd backend && uvicorn main:app --reload    # API on :8000
cd frontend && npm run dev                  # App on :3000
```

## Access Patterns

### Internal-Only (Default)
Most apps start as internal tools used by the manager's team. All users authenticate via company SSO or email/password through Supabase Auth.

### Dual-Portal (Internal + External)
When the app needs to serve both internal users and external parties (suppliers, customers, partners):

```
┌─────────────────────────────────────────────────────────┐
│                    Your Application                       │
│                                                           │
│  ┌─────────────────┐         ┌─────────────────────┐   │
│  │  Internal Portal │         │  External Portal     │   │
│  │  /app/*          │         │  /portal/*           │   │
│  │                  │         │                      │   │
│  │  Company SSO     │         │  Invite-only login   │   │
│  │  All features    │         │  Limited views       │   │
│  │  Full RBAC       │         │  Scoped RLS          │   │
│  └────────┬─────────┘         └──────────┬───────────┘   │
│           │                              │                │
│           └──────────┬───────────────────┘                │
│                      ▼                                    │
│           ┌─────────────────┐                            │
│           │   Supabase      │                            │
│           │   (shared DB,   │                            │
│           │   separate RLS) │                            │
│           └─────────────────┘                            │
└─────────────────────────────────────────────────────────┘
```

**When to use:** When a manager says "suppliers need access" or "customers should see their orders."

**How Claude scaffolds this:**
1. Creates a `/portal/` route group with its own layout
2. Adds an `external_user` role with minimal permissions
3. Creates scoped RLS policies (external users see only records linked to their organization)
4. Sets up invite-only registration for external users
5. Applies stricter rate limiting on external-facing endpoints

## Deployment Architecture

```
┌──────────────────────────────────────────────┐
│                  Vercel                        │
│                                                │
│  ┌──────────────────────────────────────┐    │
│  │  Nuxt 3 SSR + Static Assets          │    │
│  │  (frontend/ → built with nuxt build)  │    │
│  └──────────────────────────────────────┘    │
│                                                │
│  ┌──────────────────────────────────────┐    │
│  │  FastAPI Serverless Functions         │    │
│  │  (api/index.py → wraps backend/)     │    │
│  │  Routes: /api/* → Python runtime      │    │
│  └──────────────────────────────────────┘    │
│                                                │
│  Preview deploys per PR                       │
│  Production deploy on merge to main           │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│              Supabase Cloud                    │
│  ┌────────────┐ ┌──────────┐ ┌────────────┐ │
│  │ PostgreSQL  │ │   Auth   │ │  Storage   │ │
│  │ + RLS       │ │          │ │            │ │
│  ├────────────┤ ├──────────┤ ├────────────┤ │
│  │ Edge       │ │ Realtime │ │  Vault     │ │
│  │ Functions  │ │          │ │ (secrets)  │ │
│  └────────────┘ └──────────┘ └────────────┘ │
└──────────────────────────────────────────────┘
```

**How it works:** The `api/index.py` adapter imports the existing FastAPI app from `backend/main.py`. Vercel auto-detects it as an ASGI app and serves it at `/api/*`. Local development with `uvicorn` is completely unchanged — the adapter is only used by Vercel's Python runtime.

## Azure Deployment Architecture

When `DEPLOY_TARGET=azure`, the app runs as a Docker container on Azure Container Apps.

```
┌──────────────────────────────────────────────────────────┐
│                Azure Container Apps                        │
│                                                            │
│  ┌────────────────────────────────────────────────────┐   │
│  │  Docker Container                                   │   │
│  │  ┌──────────────────┐  ┌──────────────────────┐   │   │
│  │  │  Nuxt 3 SSR       │  │  FastAPI (uvicorn)    │   │   │
│  │  │  (node server)    │  │  /api/*               │   │   │
│  │  └──────────────────┘  └──────────────────────┘   │   │
│  └────────────────────────────────────────────────────┘   │
│                                                            │
│  OAuth2 Proxy (sidecar) ← Google SSO                      │
│  Forwards X-Forwarded-Email to app                        │
└──────────────────────────────────────────────────────────┘
           │                         │
           ▼                         ▼
┌──────────────────┐     ┌──────────────────────────────┐
│  Azure Blob       │     │  Shared PostgreSQL Server     │
│  Storage          │     │  schema: APP_SCHEMA           │
│  BLOB_CONTAINER   │     │  role:  APP_SCHEMA_owner      │
│  = <app_name>     │     │  (one app, one schema)        │
└──────────────────┘     └──────────────────────────────┘
```

**Authentication in Azure mode:** Google SSO is handled by OAuth2 Proxy before requests reach the app. The app receives `X-Forwarded-Email` and `X-Forwarded-User` headers. `get_current_user()` reads identity from the header instead of a Supabase JWT. RBAC (roles, permissions) is still managed via the `user_roles` table — Google is identity-only.

**App isolation:** Each app gets its own PostgreSQL schema (`APP_SCHEMA=<app_name>`) and its own Blob Storage container (`BLOB_CONTAINER=<app_name>`). Multiple apps share the same database server and storage account — IT provisions both once, each app stays isolated.

**Environment variables added for Azure mode:**

| Variable | Where | Description |
|----------|-------|-------------|
| `DEPLOY_TARGET` | Backend | Set to `azure` to enable Azure auth path |
| `APP_SCHEMA` | Backend | PostgreSQL schema name for this app (e.g. `hr_leave_tracker`) |
| `BLOB_CONTAINER` | Backend | Azure Blob Storage container name for this app |
| `AZURE_STORAGE_CONNECTION_STRING` | Backend | Azure Storage account connection string |
| `AZURE_ALLOWED_EMAIL_DOMAIN` | OAuth2 Proxy | Restricts login to this email domain (e.g. `company.com`) |
