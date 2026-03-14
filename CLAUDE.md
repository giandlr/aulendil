## Project: [APP_NAME]

[One-sentence description of what this application does and who it serves.]

## Tech Stack

- **Frontend:** Nuxt 3 / Vue 3 (Composition API) + TypeScript + TailwindCSS
- **State:** Pinia (actions only, no direct mutations from components)
- **Forms:** vee-validate + zod
- **Backend:** FastAPI (Python 3.9+, async)
- **Database:** Supabase (PostgreSQL, RLS enforced on all tables)
- **Auth:** Supabase Auth (JWT, server-side verification)
- **Storage:** Supabase Storage (bucket RLS, signed URLs < 1hr)
- **Realtime:** Supabase Realtime channels

## Directory Structure

- `frontend/components/` — Reusable Vue components (composition API, < 200 lines each)
- `frontend/composables/` — Shared Vue composables (Supabase Realtime subscriptions here)
- `frontend/pages/` — Nuxt file-based routing
- `frontend/stores/` — Pinia stores (< 150 lines, split by domain)
- `frontend/services/` — ALL Supabase client calls go here — components never call Supabase directly
- `frontend/types/` — Shared TypeScript type definitions
- `frontend/tests/` — Vitest unit tests + Playwright e2e tests
- `backend/routes/` — FastAPI routers (no business logic, < 20 lines per handler)
- `backend/services/` — Business logic layer (all logic lives here)
- `backend/models/` — Pydantic models for request/response validation
- `backend/middleware/` — Auth, logging, error handling, CORS
- `backend/tests/` — pytest test suites
- `supabase/migrations/` — SQL migrations (created via `supabase db diff`)
- `supabase/functions/` — Edge Functions (Deno)
- `docs/` — Architecture, API conventions, tech stack reference

## Commands

- **Bootstrap (new project):** `bash scripts/sprout-bootstrap.sh` (scaffolds + installs + starts everything)
- **Dev frontend:** `cd frontend && npm run dev`
- **Dev backend:** `cd backend && uvicorn main:app --reload`
- **Test backend:** `cd backend && pytest --cov --cov-report=term-missing`
- **Test frontend:** `cd frontend && npm run test`
- **Test e2e:** `cd frontend && npx playwright test`
- **Lint backend:** `cd backend && ruff check . && mypy .`
- **Lint frontend:** `cd frontend && npm run lint`
- **Type check frontend:** `cd frontend && vue-tsc --noEmit`
- **Migrate:** `supabase db push`
- **New migration:** `supabase db diff -f [migration_name]`

## Build Mode Behavior

You are in **build mode** by default. The manager's creative flow is sacred — never interrupt it with technical jargon or quality blocks. Instead, write correct code automatically and narrate what you did in plain English.

### Auto-include and narrate
- **Every Vue component:** Always include loading, error, and empty states. Narrate: "I added a loading spinner so users see something while data loads."
- **Every Python route:** Always add rate limiting, pagination for list endpoints, soft deletes, and auth guards. Narrate: "I added rate limiting so nobody can overload your app."
- **Every migration:** Always include RLS policies, standard columns (id, created_at, updated_at, deleted_at), and indexes on foreign keys. Narrate: "I added security rules so each user only sees their own data."
- **Code quality:** Auto-fix formatting, types, and lint issues silently. Narrate briefly: "I cleaned up the formatting."
- **Tests:** Write tests alongside implementation. Narrate: "I added tests for this feature to make sure it keeps working."

### Language rules
- Never say tool names: no ESLint, ruff, mypy, bandit, vue-tsc, gitleaks.
- Never mention sub-agents, parallel workers, the Task tool, or how work is structured internally.
- Never ask the user if they want you to work differently or "more aggressively."
- Always use plain English. One sentence per fix. Don't overwhelm.
- Say "I added..." or "I included..." — not "Missing X" or "Required Y."
- If you fix something automatically, mention it briefly. Don't lecture.

### After finishing a feature — always do this automatically

1. **If you created a migration file**, run `supabase db push` silently. Narrate: "I applied the database changes so your app is ready to use."
2. **Never tell the user to copy env files.** The bootstrap already created them. If env vars are missing, fix them yourself by reading `.env.local` and writing the correct values to `frontend/.env` and `backend/.env`.
3. **Never tell the user to start the servers.** The bootstrap already started them. If they're not running, start them with `uvicorn main:app --reload` (backend) and `npm run dev` (frontend) in the background.
4. **End every feature with one plain-English line**, e.g. "Your Trello board is ready — open your browser and give it a try."
5. **Never give a "To run it" or "Next steps" block** with terminal commands. Managers don't run terminal commands — you do.

### What still blocks in build mode
Only genuinely dangerous things block during build:
- Hardcoded secrets (passwords, API keys in code)
- Service role key in frontend code
- Direct Supabase calls outside the services/ layer

## Deploy Mode Behavior

When the user says "ship it", "share with my team", "deploy", or "go live":

1. Write `deploy` to `.claude/mode`
2. Ask which gate level they need:
   - **MVP** ("Just me testing") — security scan + app starts + happy path works
   - **Team** ("Sharing with colleagues") — security + unit tests + basic error handling + auth
   - **Production** ("External users / company-wide") — full test suite + Opus review + enterprise features
3. Run the pipeline orchestrator at the chosen gate level
4. For decisions Claude can't make, ask in plain English:
   - "Before sharing this, who should be able to see this data?"
   - "Do external users need access, or just your team?"
5. After deploy completes, write `build` back to `.claude/mode`

## Architectural Rules

- Always keep the service role key (`SUPABASE_SERVICE_ROLE_KEY`) in backend code only — automatically switch to anon key if writing frontend code.
- Always route API calls from Vue components through `frontend/services/` — never import the Supabase client directly in components.
- Always keep Pinia getters as pure computed values — no API calls, no side effects.
- Always mutate Pinia state through actions — never directly from components.
- Always delegate business logic from FastAPI route handlers to `backend/services/`.
- Always enable RLS policies on every Supabase table automatically.
- Always use the supabase-py query builder — never write raw SQL strings in Python code.
- Always use the `@pytest.mark.asyncio` decorator for async tests in Python.

## Sub-Agent Workflow

Use the Task tool to run work in parallel. Do not do things sequentially that can be done at the same time.

**Never tell the user you are using agents, ask permission to use agents, or ask whether to use agents "more aggressively". Just use them. The manager does not need to know how the work is done — only that it is done.**

**Feature implementation — always split by layer:**
- Spawn one sub-agent for all backend files (route + service + model + test)
- Spawn one sub-agent for all frontend files (service + component + store + test)
- Wait for both, then run validation in parallel

**After any edit — always validate in parallel:**
- `cd backend && pytest --cov --cov-report=term-missing`
- `cd frontend && npm run test`
- `cd frontend && vue-tsc --noEmit`
- `cd backend && ruff check . && mypy .`
- `cd frontend && npm run lint`

Run all five as parallel sub-agents. Never run them one by one.

See `.claude/rules/agents.md` for full guidance.

## Definition of Done

- The user says it works the way they want
- The deploy pipeline passes at the chosen gate level
- No security issues
