## Tech Stack

- **Frontend:** Nuxt 3 / Vue 3 (Composition API) + TypeScript + TailwindCSS
- **State:** Pinia (actions only, no direct mutations from components)
- **Forms:** vee-validate + zod
- **Backend:** FastAPI (Python 3.9+, async) — or ASP.NET Core 8 when `BACKEND_LANGUAGE=csharp`
- **Mobile (optional):** Flutter (iOS + Android) — scaffolded into `mobile/` when selected
- **Database:** Supabase (PostgreSQL, RLS enforced on all tables)
- **Auth:** Supabase Auth (JWT, server-side verification)
- **Storage:** Supabase Storage (bucket RLS, signed URLs < 1hr)
- **Realtime:** Supabase Realtime channels

## Directory Structure

- `frontend/components/` — Vue components (composition API, < 200 lines)
- `frontend/composables/` — Shared composables (Realtime subscriptions here)
- `frontend/pages/` — Nuxt file-based routing
- `frontend/stores/` — Pinia stores (< 150 lines, split by domain)
- `frontend/services/` — ALL Supabase client calls — components never call Supabase directly
- `frontend/types/` — Shared TypeScript types
- `frontend/tests/` — Vitest + Playwright tests
- `backend/routes/` — FastAPI routers (no business logic, < 20 lines per handler) **[Python]**
- `backend/services/` — Business logic layer
- `backend/models/` — Pydantic request/response models **[Python]** / record DTOs **[C#]**
- `backend/middleware/` — Auth, logging, error handling, CORS
- `backend/tests/` — pytest suites **[Python]** / xUnit **[C#]**
- `backend/Routes/` — ASP.NET Core endpoint maps **[C# only]**
- `backend/Data/` — EF Core DbContext + Migrations **[C# only]**
- `mobile/lib/features/` — Flutter feature modules (data / domain / presentation) **[mobile only]**
- `mobile/lib/core/` — Shared Flutter services, auth, router **[mobile only]**
- `supabase/migrations/` — SQL migrations (`supabase db diff`)
- `supabase/functions/` — Edge Functions (Deno)

## Commands

- **Bootstrap:** `bash scripts/bootstrap.sh`
- **Dev frontend:** `cd frontend && npm run dev`
- **Dev backend (Python):** `cd backend && uvicorn main:app --reload`
- **Dev backend (C#):** `cd backend && dotnet run`
- **Dev mobile:** `cd mobile && flutter run`
- **Test backend (Python):** `cd backend && pytest --cov --cov-report=term-missing`
- **Test backend (C#):** `cd backend && dotnet test --collect:"XPlat Code Coverage"`
- **Test frontend:** `cd frontend && npm run test`
- **Test e2e:** `cd frontend && npx playwright test`
- **Test mobile:** `cd mobile && flutter test --coverage`
- **Lint backend (Python):** `cd backend && ruff check . && mypy .`
- **Lint backend (C#):** `cd backend && dotnet format --verify-no-changes`
- **Lint frontend:** `cd frontend && npm run lint`
- **Lint mobile:** `cd mobile && flutter analyze && dart format --set-exit-if-changed .`
- **Type check frontend:** `cd frontend && vue-tsc --noEmit`
- **Migrate (Supabase/Python):** `supabase db push`
- **New migration (Supabase/Python):** `supabase db diff -f [migration_name]`
- **Migrate (C#):** `cd backend && dotnet ef database update`
- **New migration (C#):** `cd backend && dotnet ef migrations add [migration_name]`

## Discovery Mode

**Trigger:** User says "build me...", "I want...", "create...", "make me..." AND project is greenfield (`[APP_NAME]` placeholder still present in CLAUDE.md or no migrations exist).

**Round 1 — Big Picture (2 questions via AskUserQuestion with clickable options):**
- "What kind of app is this closest to?" (dashboard / form tool / communication tool / scheduling tool / other)
- "Who will use this?" (just me / my team / team + external people)

**Round 2 — Core Features + Baseline (3–4 questions):**
- Present feature options as multi-select based on Round 1
- Challenge: "Is there anything I'm missing? Any approval workflows or external system connections?"
- "Do you need a mobile app?" (yes — mobile + web / web only)
- "Which backend?" (Python — faster for small teams / C# — better for enterprise scale)
- **Production baseline checklist** (see `production-baseline.md`): Based on the audience answer from Round 1, present the applicable baseline features as a yes/no checklist via AskUserQuestion. Frame as: "Here are a few things users almost always expect — which should I include?" For team/external apps this must include: forgot password, user management page, role assignment, user deactivation. For external apps also include: email verification, invite flow.

*Mobile answer writes `INCLUDE_MOBILE=true` to `.env`; backend answer writes `BACKEND_LANGUAGE=python` or `BACKEND_LANGUAGE=csharp` to `.env`. Bootstrap reads these on next run.*

**Round 3 — Data & Access (1 question):**
- "Should everyone see everything, or only their own stuff?" (everyone / own only / role-based)

**Skip condition:** If initial request has 3+ features AND mentions audience, still run the baseline checklist — never skip it for team/external apps.

**Output:** Write `.claude/brief.md` with: app name, description, users, features (including confirmed baseline features), data model sketch, access rules, out-of-scope. Update `[APP_NAME]` in CLAUDE.md, write `build` to `.claude/mode`, narrate plan, ask "Does this look right?"

## Build Mode

Default mode. Write correct code automatically, narrate in plain English.

**Clarify before building — mandatory for new features:** Before writing any new feature, ask 1–2 focused questions via AskUserQuestion to confirm scope and behavior. Do not start building until these are answered. Good questions cover: who can do this action (all users or admins only?), what happens in the edge case (what if the item is already deleted?), and any specific UI expectation (table or cards?). Keep questions short with clickable options where possible. Skip clarification only for trivially obvious tasks (e.g. "fix that typo").

**When to skip clarification:**
- UI-only changes (styling, layout, text updates)
- Bug fixes to existing features
- Adding a field to an existing form/table
- Features where `.claude/brief.md` already specifies behavior

**Always clarify for:**
- New database tables or data structures
- Permission/access scope changes
- External service integrations
- Features affecting multiple layers (frontend + backend + migration)

**Auto-include:** Loading/error/empty states in Vue components, rate limiting + pagination + soft deletes + auth guards in Python/C# routes, RLS + standard columns + FK indexes in migrations, tests alongside implementation. For Flutter: Riverpod providers in `domain/`, repositories in `data/`, screens in `presentation/`. Narrate each in one sentence.

**Production baseline:** After building the first substantive feature in a new project, check `production-baseline.md` against the audience confirmed in Discovery. If baseline features (forgot password, user management, role assignment, etc.) have not been built yet, flag them in plain English and offer to add them before moving on. Never silently skip this check.

**Validate after every feature — mandatory:** After writing files for any feature, run tests + lint + type-check in parallel (see agents.md). Fix every failure before responding. Never hand back code that doesn't pass. The user should never see a broken state.

**Contextual validation narration:** When validation fails, narrate in context of the current gate level. Example: "Tests are at 58% coverage — we need 60% for the MVP gate. I'm adding 2 tests to get us there." If the failure doesn't block the current gate, say so: "This lint warning won't block deployment, but let me fix it to keep things clean."

**Project status dashboard:** After completing any feature, update `.claude/status.md` with the current state of baseline and core features. Mark completed items with `[x]`. This file is the manager's at-a-glance project dashboard — keep it accurate.

**Language:** No tool names, no sub-agent mentions, no "Missing X" — say "I added...". Plain English, one sentence per fix.

**Secrets:** Write placeholder in env file, ask user for the one key they need, handle everything else automatically.

**After features:** Run `supabase db push` if migration created. Fix env vars yourself. Start servers if needed. End with one plain-English line. Never give "Next steps" blocks.

**Multi-layer summary:** After completing a feature that touches 2+ layers, end with a one-line-per-layer summary:
> "Done. Here's what I added:
> - Database: `tasks` table with RLS policies
> - Backend: `GET/POST/PATCH /api/tasks` with auth
> - Frontend: Task board page at `/app/tasks`"

**Blocks:** Hardcoded secrets, service role key in frontend, direct Supabase calls outside services/ (web) or features/*/data/ (mobile), raw SQL string concatenation in C#, business logic in C# route handlers.

## Deploy Mode

Trigger: "ship it", "deploy", "go live". Write `deploy` to `.claude/mode`.

1. **If `DEPLOY_TARGET` is not set in `.env`:** Ask (AskUserQuestion) "Where do you want to put the app?" with options: "On the company server" / "In the cloud". Set `DEPLOY_TARGET=azure` or `DEPLOY_TARGET=vercel` in `.env` — this setting sticks until changed.
2. Ask up to 2 more questions via AskUserQuestion with clickable options to determine gate level (mvp/team/production).
3. Run `bash .claude/scripts/run-pipeline.sh <gate>` (reads `DEPLOY_TARGET` from env).
4. Write `build` back to `.claude/mode` when done.

**Language rule:** Say "company server" when referring to Azure. Say "cloud" when referring to Vercel. Never say the technical names in conversation. Say "switch to the company server" / "switch to the cloud" for target changes.

**Switch anytime:** If the manager says "switch to the company server" or "switch to the cloud", update `DEPLOY_TARGET` in `.env` and confirm in plain English.

## Cloud Deploy Mode

Trigger: "deploy to cloud", "make this live", "put it online", "go live" (when context implies cloud deployment, not local).

**Skip condition:** If `DEPLOY_TARGET` is already set → skip target discovery, go straight to the appropriate path.

### Path A — Cloud (Vercel)

**Skip condition:** If `vercel.json` exists AND `deploy-state.json` shows previous cloud deploy → skip discovery, go straight to deploy.

**Discovery (AskUserQuestion):**
- Round 1: "Do you have a Vercel account?" (Yes / No / IT handles this) + "Do you have a Supabase Cloud project?" (Yes / No / Not sure)
- Round 2: "Where should this go?" (Staging / Production)

**Three paths:**
1. **Self-service** (has accounts): `scaffold-cloud-configs.sh` → `run-pipeline.sh` → `deploy-cloud.sh`
2. **IT handoff** (IT handles infra): `scaffold-cloud-configs.sh` → `generate-handoff-doc.sh` → narrate "I created a setup guide for your IT team"
3. **Guided setup** (unsure): `generate-handoff-doc.sh` → `scaffold-cloud-configs.sh` → narrate what they need

**Architecture:** Frontend (Nuxt 3 SSR) + Backend (FastAPI serverless) both deploy to Vercel. Database on Supabase Cloud.

### Path B — Company Server (Azure)

**Skip condition:** If `azure-container-app.yml` exists AND `deploy-state.json` shows previous azure deploy → skip discovery, go straight to deploy.

**Discovery (AskUserQuestion):**
- Round 1: "Does your IT team have Azure set up?" (Yes / No / Not sure) + "Do you have a Google Workspace account for company login?" (Yes / No)
- Round 2: "Where should this go?" (Staging / Production)

**Three paths:**
1. **Self-service** (IT has Azure): `scaffold-azure-configs.sh` → `run-pipeline.sh` (DEPLOY_TARGET=azure) → `deploy-azure.sh`
2. **IT handoff** (IT handles infra): `scaffold-azure-configs.sh` → `generate-azure-handoff-doc.sh` → narrate "I created a setup guide for your IT team"
3. **Guided setup** (unsure): `generate-azure-handoff-doc.sh` → `scaffold-azure-configs.sh` → narrate what they need

**Architecture:** App runs as a Docker container on Azure Container Apps. Google SSO is handled automatically — employees log in with their company email. Database isolated per app via `APP_SCHEMA`.

## Architectural Rules

- Service role key (`SUPABASE_SERVICE_ROLE_KEY`) stays in backend only — auto-switch to anon key in frontend.

*All other rules (service layer, Pinia, RLS, query builder, etc.) are in the other files in this directory.*

## Sub-Agent Workflow

See `.claude/rules/agents.md` for full guidance. Never mention agents to the user.

## Session Lifecycle

On session start, check `.claude/session/latest.json`:
- If `status: "in_progress"`, read the checkpoint and offer to resume: "It looks like we were working on [task]. Want to pick up where we left off?"
- If `status: "completed"` but `git status` shows uncommitted changes, offer: "We finished [task] but the changes aren't committed yet. Want me to review and commit?"
- If `latest.json` is missing but `.claude/session/file-log.txt` is non-empty, infer crash — read file log + `git status` and offer recovery.

Progress tracking: Write `.claude/session/plan.md` with checkboxes for multi-step tasks. On resume, check file existence and box state.

**Session checkpoint schema** (`.claude/session/latest.json`):
```json
{
  "status": "in_progress | completed | failed",
  "task": "Short description of current task",
  "checkpoint": "Last completed step or milestone",
  "files_modified": ["path/to/file1.ts", "path/to/file2.py"],
  "timestamp": "2026-03-17T14:30:00Z"
}
```

**Error recovery:** Pipeline and deploy scripts write `.claude/last-error.json` on failure:
```json
{
  "timestamp": "2026-03-17T14:30:00Z",
  "stage": "deploy-azure",
  "error": "Docker push failed",
  "log_file": ".claude/tmp/docker-build.log",
  "recovery": "Check ACR credentials and retry"
}
```
On session start, if this file exists, read it and offer recovery: *"It looks like the last deployment failed at [stage]. Want me to retry?"* Delete the file after successful recovery.

**First-run detection:** On first session in a greenfield project (no `.claude/brief.md`, `[APP_NAME]` placeholder still in CLAUDE.md), start with:
> "Welcome! I'll help you build your app. First, I have a few quick questions about what you need."
> If `manual/guide.html` exists, add: "For a visual overview, open manual/guide.html in your browser."

## Definition of Done

- User says it works
- Deploy pipeline passes at chosen gate level
- No security issues
