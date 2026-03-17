# Aulendil

**Build enterprise apps by describing what you want in plain English.** Quality, security, and testing happen automatically behind the scenes.

This toolkit turns [Claude Code](https://docs.anthropic.com/en/docs/claude-code) into a full engineering team for non-technical managers. You describe features in natural language, Claude builds production-quality code, and an automated pipeline ensures everything works before you share it.

---

## Quick Start

```bash
# 1. Create a new project and initialize git
mkdir my-app && cd my-app && git init

# 2. Copy the toolkit zip and unzip it (creates aulendil/ folder)
cp /path/to/aulendil.zip .
unzip aulendil.zip

# 3. Install the toolkit (copies files, sets up .gitignore, cleans up)
bash aulendil/install.sh

# 4. Bootstrap your app (scaffolds everything + starts the servers)
bash scripts/bootstrap.sh

# 5. Open CLAUDE.md and replace [APP_NAME] with your app's name

# 6. Open Claude Code and start building
claude
```

After bootstrap completes, your app is already running:

| Service         | URL                          |
|-----------------|------------------------------|
| Frontend        | http://localhost:3000         |
| Backend API     | http://localhost:8000         |
| API Docs        | http://localhost:8000/docs    |
| Supabase Studio | http://localhost:54323        |

A development user (`dev@aulendil.local` / `devpassword123`) is seeded automatically for local testing.

> **Note:** Toolkit files are automatically excluded from git. When you commit or deploy, only your project's source code is included — never the fleet infrastructure.

---

## How It Works

### Three Phases

| Phase | When | What Happens |
|-------|------|--------------|
| **Discovery** | New project, first conversation | Claude asks 2-3 rounds of clickable questions to understand what you want, then writes a project brief for your approval before building. |
| **Build** (default) | You're creating features | Build freely. Only security issues are blocked. Claude auto-fixes quality and explains what it did in plain English. |
| **Deploy** | You say "ship it" | Claude asks who it's for and runs the appropriate level of checks before sharing. |

### Three Deploy Levels

| Level | Who It's For | What's Checked |
|-------|-------------|----------------|
| **MVP** | Just you testing | Security scan, smoke test, unit tests, integration tests, e2e tests (60/50 coverage) |
| **Team** | Sharing with colleagues | Everything in MVP + RBAC check + Opus code review |
| **Production** | External users | Everything in Team + performance tests + all enterprise features |

Start at MVP and graduate to Production as your project matures.

### Session Recovery

If your terminal closes or crashes, Claude automatically saves a checkpoint. When you reopen Claude Code, it offers to pick up where you left off — no work is lost.

---

## What's Inside

```
your-project/
├── .claude/
│   ├── agents/                 # Specialist AI workers (tests, pipeline, review)
│   ├── hooks/                  # Real-time guards (security, quality)
│   │   └── lib/                # Shared hook utilities
│   ├── rules/                  # Domain-specific standards (API, auth, DB, frontend, workflow)
│   │   └── workflow.md         # Modes, commands, tech stack — updated on every framework upgrade
│   ├── reviewers/              # Opus code reviewer system prompt
│   ├── scripts/                # Pipeline scripts (security, smoke test, review, release)
│   ├── session/                # Crash recovery checkpoints (gitignored)
│   ├── settings.json           # Claude Code permissions
│   ├── mode                    # Current mode: "build" or "deploy"
│   ├── version                 # Installed framework version (e.g. 1.5.0)
│   └── deploy-gates.json       # Gate level definitions (MVP/Team/Production)
├── docs/
│   ├── architecture.md         # System architecture reference
│   ├── api-conventions.md      # API design standards
│   ├── tech-stack.md           # Technology decisions (single source of truth)
│   ├── done-checklist.md       # Definition of done per gate level
│   ├── enterprise-features.md  # Enterprise feature requirements
│   └── changelog-guide.md      # Changelog conventions
├── scripts/
│   ├── bootstrap.sh            # One-command project setup
│   └── stop.sh                 # Stop background servers
├── manual/
│   └── guide.html              # Visual guide (open in browser, 32 slides)
├── CLAUDE.md                   # App name + project notes (6 lines — never overwritten by updates)
├── CHANGELOG.md                # Auto-maintained release history
├── VERSION                     # Framework version number
├── update.sh                   # Framework updater (safe in-place upgrade)
└── install.sh                  # Toolkit installer
```

> All toolkit files (`.claude/`, `CLAUDE.md`, `docs/`, `scripts/`, `update.sh`, `VERSION`) are gitignored after install. Only your app's source code gets committed.

---

## Tech Stack

The toolkit scaffolds projects with:

- **Frontend:** Nuxt 3 / Vue 3 (Composition API) + TypeScript + TailwindCSS
- **Mobile (optional):** Flutter (iOS + Android) — Riverpod state, supabase_flutter, go_router
- **State:** Pinia (web) / Riverpod 2 (mobile)
- **Forms:** vee-validate + zod
- **Backend:** FastAPI (Python 3.9+, async) **or** ASP.NET Core 8 Minimal APIs + EF Core (C#)
- **Database:** Supabase (PostgreSQL with Row Level Security)
- **Auth:** Supabase Auth (JWT) + RBAC (4 default roles)
- **Testing:** Vitest + Playwright (frontend), pytest / xUnit (backend), flutter_test (mobile)
- **Quality:** ESLint, Prettier, vue-tsc, ruff, mypy, bandit (Python) / dotnet format, Roslyn (C#), flutter analyze (mobile)
- **Hosting:** Cloud (Vercel + Supabase Cloud) or Company Server (Azure Container Apps)

All technology decisions are defined in `docs/tech-stack.md`.

---

## The Bootstrap Script

`scripts/bootstrap.sh` takes you from an empty project to a running app in one command:

| Phase | What It Does |
|-------|-------------|
| **1. Scaffold** | Creates Nuxt 3 frontend, FastAPI backend, and Supabase directory structure |
| **2. Configure** | Installs all dependencies, creates config files, sets up dev plugins, writes `SETUP.md` |
| **3. Supabase** | Initializes and starts local Supabase, extracts credentials, seeds a dev user |
| **4. Start** | Launches backend and frontend dev servers in the background — output goes to `logs/backend.log` and `logs/frontend.log`, terminal stays usable |
| **5. Dev Tools** | Installs gitleaks, k6, and sets file permissions |

### Prerequisites

- **Node.js** (18+)
- **Python** (3.9+)
- **Docker** (for local Supabase)
- **Flutter SDK** (3.x+) — only when `INCLUDE_MOBILE=true`
- **Xcode** (iOS development) — only when building for iOS
- **Android Studio** (Android development) — only when building for Android

Docker is optional during build mode — the app works as a UI shell without a database, showing empty states and an informational banner. Supabase is required at the Team and Production deploy levels.

---

## Updating the Framework

When a new version of Aulendil is released, update any existing project with three commands:

```bash
unzip aulendil.zip
bash aulendil/update.sh
```

The updater replaces only framework-owned files — scripts, hooks, rules, agents, reviewers. It never touches:

- `CLAUDE.md` — your app name and project notes stay intact
- `.env` — your secrets are safe
- `.claude/mode` — your current build/deploy state is preserved
- All of `frontend/`, `backend/`, `mobile/` — your code is untouched

After the update, no re-bootstrap is needed. The terminal shows "Updated: v1.4.0 → v1.5.0" when complete.

To check which version a project is on: `cat .claude/version`

---

## Protection Layers

### Layer 1 — Rules
Claude automatically follows project standards for API design, authentication, database patterns, and frontend conventions. Defined in `.claude/rules/`.

### Layer 2 — Guards (Hooks)
Real-time checks on every code write and command execution. Block messages are two-part: what was blocked AND what Claude will do instead.
- **Always blocked:** Hardcoded secrets, dangerous commands, admin keys in frontend, SQL injection, eval()
- **Build mode warnings (deploy blocks):** Unsafe CORS, missing RLS, unindexed foreign keys, console.log, missing error handling, unbounded queries

### Layer 3 — Specialist Agents
Parallel AI workers for tests, security scans, and performance checks. The pipeline orchestrator coordinates them without touching code itself.

### Layer 4 — Pipeline
Gate-level validation when you deploy. The pipeline accepts a gate level (`mvp`, `team`, `production`) and runs only the stages required for that level.

### Layer 5 — Opus Review (Team and Production)
An independent AI reviewer (Claude Opus) examines the code with zero knowledge of the development session. Like an external auditor. Runs with a 5-minute timeout.

---

## Key Commands

| Action | Command |
|--------|---------|
| Start frontend | `cd frontend && npm run dev` |
| Start backend | `cd backend && uvicorn main:app --reload` |
| Run backend tests | `cd backend && pytest --cov --cov-report=term-missing` |
| Run frontend tests | `cd frontend && npm run test` |
| Run e2e tests | `cd frontend && npx playwright test` |
| Lint backend | `cd backend && ruff check . && mypy .` |
| Lint frontend | `cd frontend && npm run lint` |
| Type check frontend | `cd frontend && vue-tsc --noEmit` |
| Run migrations | `supabase db push` |
| Create migration | `supabase db diff -f [name]` |
| Tag a release | `bash .claude/scripts/tag-release.sh v1.0.0` |
| Record deployment | `bash .claude/scripts/mark-deployed.sh production` |
| Run pipeline | `bash .claude/scripts/run-pipeline.sh [mvp\|team\|production]` |
| Stop servers | `bash scripts/stop.sh` |
| Security scan | `bash .claude/scripts/security-scan.sh` |
| Repackage toolkit | `bash scripts/package.sh` |
| Update framework | `bash aulendil/update.sh` |

---

## Deployment

The toolkit supports two deployment targets. Claude asks "company server or cloud?" when you say "ship it" — your choice sticks until you change it.

### Cloud (Vercel)

```
Vercel (single platform)
├── Nuxt 3 SSR (frontend/)
└── FastAPI Serverless (api/index.py wraps backend/)

Supabase Cloud
└── PostgreSQL + Auth + Storage + Realtime
```

**Three deployment paths:**
- **Self-service:** You have Vercel + Supabase accounts → scaffold configs → pipeline → deploy
- **IT handoff:** Your IT team handles infrastructure → auto-generated setup guide
- **Guided setup:** Not sure → full handoff doc + configs ready for when you are

Say "deploy to cloud" or "make this live" to start. Estimated cloud costs: Vercel Pro ~$20/mo (estimated), Supabase Pro ~$25/mo (estimated).

| Command | What It Does |
|---------|-------------|
| `bash .claude/scripts/scaffold-cloud-configs.sh` | Creates vercel.json, API adapter, CORS config |
| `bash .claude/scripts/deploy-cloud.sh [staging\|production]` | Deploys to Vercel |
| `bash .claude/scripts/setup-supabase-cloud.sh <ref>` | Links + pushes to Supabase Cloud |
| `bash .claude/scripts/generate-handoff-doc.sh` | Creates IT setup guide |

### Company Server (Azure)

```
Azure Container Apps
└── Docker Container
    ├── Nuxt 3 SSR
    └── FastAPI (uvicorn)
    OAuth2 Proxy (sidecar) — handles Google SSO automatically

Azure Database for PostgreSQL
└── Shared server, one schema per app (APP_SCHEMA)

Azure Blob Storage
└── One container per app (BLOB_CONTAINER)
```

**For companies already on Azure + Google Workspace.** Employees log in with their company email automatically — no extra accounts needed. Each app stays isolated on the shared infrastructure.

**Three deployment paths:**
- **Self-service:** IT has Azure set up → scaffold configs → pipeline → deploy
- **IT handoff:** IT handles infrastructure → auto-generated setup guide
- **Guided setup:** Not sure → full handoff doc + configs ready for when you are

Say "put this on the company server" or "make this live" to start. Estimated costs: ~$15–30/mo per app (estimated — see [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/)).

| Command | What It Does |
|---------|-------------|
| `bash .claude/scripts/scaffold-azure-configs.sh` | Creates Dockerfile, docker-compose, env template, Container App config |
| `bash .claude/scripts/deploy-azure.sh [staging\|production]` | Builds image → pushes to ACR → updates Container App |
| `bash .claude/scripts/setup-azure-db.sh <app-schema>` | Creates per-app schema and database role |
| `bash .claude/scripts/generate-azure-handoff-doc.sh` | Creates IT setup guide for Azure |

---

## Playwright E2E Testing

Bootstrap automatically installs Playwright (chromium-only) and creates starter test patterns:

- **`tests/e2e/auth.spec.ts`** — Login flow, auth redirect, session handling
- **`tests/e2e/smoke.spec.ts`** — Page load + accessibility checks (axe-core)
- **`tests/e2e/forms.spec.ts`** — Form validation patterns

Tests run as part of the pipeline at all gate levels (MVP and above). Claude adapts the starter patterns to your actual app during build.

| Command | What It Does |
|---------|-------------|
| `cd frontend && npm run test:e2e` | Run e2e tests |
| `cd frontend && npm run test:e2e:ui` | Run with interactive UI |

---

## RBAC (Role-Based Access Control)

Bootstrap creates a complete RBAC foundation with 4 default roles:

| Role | Permissions |
|------|------------|
| **Admin** | Full access to all resources |
| **Manager** | Manage team members and resources |
| **Member** | View and edit own resources |
| **Viewer** | Read-only access |

The dev user (`dev@aulendil.local`) is automatically assigned the admin role. Claude adds app-specific RLS policies and role-aware features during build.

**Backend:** `require_role("admin")` FastAPI dependency for protected endpoints.
**Frontend:** `useRole()` composable for role-aware UI rendering.

---

## The Manual

Open `manual/guide.html` in any browser for a visual walkthrough of the entire system (32 slides). Navigate with arrow keys or click the dots. Works offline — no external dependencies.

---

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed release notes.

- **v1.7** — Pipeline gate integrity (RBAC/schema checks now block deploys), security hardening, bootstrap checkpoint/resume, Docker-optional bootstrap, `preflight-check.sh`, `check-gate.sh`, debug mode, 5 new C# rule sections
- **v1.6** — Production baseline (forgot password, user management, RBAC), clarify-before-building, full test suite at every gate level (MVP/Team/Production), Opus review now at Team+, 6 bootstrap fixes (Tailwind, DevTools, env validation, app seed, SETUP.md, dev auth warning)
- **v1.5** — Framework updater (`update.sh`), version tracking, background server logs, mandatory post-feature validation, `CLAUDE.md` reduced to project identity only (framework rules now in `.claude/rules/workflow.md` — updated automatically)
- **v1.4** — Flutter mobile (iOS + Android) option, C# / ASP.NET Core 8 backend option, updated manual (32 slides)
- **v1.3** — Azure deployment target (company server), dual-mode auth (Google SSO via OAuth2 Proxy), per-app schema isolation, 4 new Azure scripts, updated manual (26 slides)
- **v1.2** — Cloud deployment (Vercel + Supabase Cloud), Playwright e2e testing with starter patterns, RBAC foundation (4 default roles), IT handoff doc generator, updated manual (22 slides)
- **v1.1** — Discovery mode, session recovery, compressed instructions (~56% token reduction), gate-aware deploy pipeline, 6 new hook detections, two-part error messages, updated manual (20 slides)
- **v1.0** — Initial release with build/deploy modes, three gate levels, Opus code review, hook system, bootstrap script

---

## Philosophy

> "The best engineering practices shouldn't require an engineering degree."

- **Discover first** — Before building, Claude asks the right questions to understand what you want.
- **Build freely** — Your creative flow is sacred. Quality enforcement stays out of your way during development.
- **Deploy safely** — When you're ready to share, the right level of checks activates automatically.
- **Plain English always** — Claude never mentions tool names or technical jargon. It explains what it did and why in language anyone can understand.
- **Progressive gates** — Start simple with MVP, graduate to Production when ready. The system grows with you.
- **Nothing lost** — Session checkpoints mean crashes and terminal closes don't cost you progress.
