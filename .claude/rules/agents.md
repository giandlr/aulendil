## Sub-Agents for Parallel Work

Use Task tool aggressively — sub-agents run in parallel and cut wall-clock time.

### Mode-Aware Validation

**Build mode:** Always validate after every feature implementation. Run tests + lint + type-check in parallel, fix any failures, then respond to the user. Never hand back broken code.
**Deploy mode:** Always run full parallel validation suite before gating.

### When to Parallelize

- Frontend + backend code for same feature
- Frontend + mobile code for same feature (web + mobile layers are independent)
- Tests + linting + type-checking after edits
- Scaffolding files that don't import each other
- Exploring unrelated parts of the codebase

### Feature Implementation

1. Plan — identify all files to change
2. Split by layer — backend agent (route + service + model + test) and frontend agent (service + component + store + test) in parallel
3. Validate in parallel — pytest, vitest, vue-tsc, ruff+mypy, eslint — **mandatory every time**
4. Fix in parallel — separate agents for each failing file, then re-validate until clean
5. Only respond to the user once all checks pass

### Validation Commands (run as parallel sub-agents)

**Python backend:**
- `cd backend && pytest --cov --cov-report=term-missing`
- `cd backend && ruff check . && mypy .`

**Frontend (Nuxt — default):**
- `cd frontend && npm run test`
- `cd frontend && vue-tsc --noEmit`
- `cd frontend && npm run lint`
- `cd frontend && npx playwright test` (when Playwright config exists and feature touches UI)

**Frontend (Next.js — when FRONTEND_FRAMEWORK=next):**
- `cd frontend && npm run test`
- `cd frontend && tsc --noEmit`
- `cd frontend && npm run lint`
- `cd frontend && npx playwright test` (when Playwright config exists and feature touches UI)

**Mobile (when mobile/ exists):**
- `cd mobile && flutter test --coverage`
- `cd mobile && flutter analyze && dart format --set-exit-if-changed .`

### Escalation

If validation fails due to **infrastructure** (Docker not running, Supabase connection refused, port conflict, missing system dependency) rather than code errors, do not loop trying to fix it. Instead:
1. Explain the infrastructure issue in plain English
2. Tell the user what needs to be fixed in their environment
3. Offer to re-validate once they confirm the fix

### Pre-Build Check

Before writing any backend or frontend code, verify the environment is ready:
- **Python backend:** Check `backend/requirements.txt` exists AND `backend/.venv/` or site-packages contain FastAPI. If not, prompt: "Run `bash scripts/bootstrap.sh` first — the backend dependencies aren't installed yet."
- **Frontend:** Check `frontend/node_modules/` exists. If not, prompt: "Run `bash scripts/bootstrap.sh` first — frontend dependencies aren't installed yet."
- **Frontend stack mismatch:** If `.env` says `FRONTEND_FRAMEWORK=next` but `frontend/` contains `nuxt.config.ts` (or vice versa — `.env` says `nuxt` but `frontend/` has `next.config.ts`), warn: "The frontend is scaffolded for [X] but your .env says [Y]. Run `bash scripts/bootstrap.sh --fresh` to re-scaffold."

### Scope Rules

- Each agent: single, clear responsibility
- No assumptions about other agents — pass explicit paths/interfaces
- If agent A writes a file agent B imports, A finishes first

### When NOT to Use

- Simple single-file edits
- Strict dependency chains
- Interactive decisions based on partial results
