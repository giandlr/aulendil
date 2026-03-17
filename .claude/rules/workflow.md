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

Full Discovery flow (3 rounds of questions): read `.claude/refs/discovery-mode.md` before starting Discovery.

**Key rules:** Round 1 asks 2 questions (app type + audience). Round 2 covers features, mobile, backend language, and the production baseline checklist. Round 3 covers data access. Never skip the baseline checklist for team/external apps. Output: `.claude/brief.md`.

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

**Trigger:** "ship it", "deploy", "go live". Full deploy flow: read `.claude/refs/deploy-mode.md`.

**Key rules:**
1. If `DEPLOY_TARGET` not set: ask "company server or cloud?" — set in `.env`
2. Ask gate level (mvp/team/production)
3. Run `bash .claude/scripts/run-pipeline.sh <gate>`
4. Write `build` back to `.claude/mode` when done

**Language:** Say "company server" for Azure, "cloud" for Vercel. Never use technical names.

**Cloud (Vercel):** Frontend + Backend on Vercel, DB on Supabase Cloud.
**Company Server (Azure):** Docker on Azure Container Apps, Google SSO via OAuth2 Proxy, schema isolation per app.

## Architectural Rules

- Service role key (`SUPABASE_SERVICE_ROLE_KEY`) stays in backend only — auto-switch to anon key in frontend.

*All other rules (service layer, Pinia, RLS, query builder, etc.) are in the other files in this directory.*

## Sub-Agent Workflow

See `.claude/rules/agents.md` for full guidance. Never mention agents to the user.

## Session Lifecycle

On session start, check `.claude/session/latest.json` for resume or crash recovery. Full spec: `.claude/refs/session-lifecycle.md`.

**Quick rules:** `status: "in_progress"` → offer resume. Missing file + non-empty `file-log.txt` → crash recovery. `status: "completed"` + uncommitted changes → offer commit. Greenfield project → welcome message.

## Definition of Done

- User says it works
- Deploy pipeline passes at chosen gate level
- No security issues
