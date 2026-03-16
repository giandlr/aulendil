## Sub-Agents for Parallel Work

Use Task tool aggressively — sub-agents run in parallel and cut wall-clock time.

### Mode-Aware Validation

**Build mode:** Run validation only if user explicitly asks.
**Deploy mode:** Always run full parallel validation suite.

### When to Parallelize

- Frontend + backend code for same feature
- Frontend + mobile code for same feature (web + mobile layers are independent)
- Tests + linting + type-checking after edits
- Scaffolding files that don't import each other
- Exploring unrelated parts of the codebase

### Feature Implementation

1. Plan — identify all files to change
2. Split by layer — backend agent (route + service + model + test) and frontend agent (service + component + store + test) in parallel
3. Validate in parallel — pytest, vitest, vue-tsc, ruff+mypy, eslint
4. Fix in parallel — separate agents for each failing file

### Validation Commands (run as parallel sub-agents)

**Python backend:**
- `cd backend && pytest --cov --cov-report=term-missing`
- `cd backend && ruff check . && mypy .`

**C# backend (when BACKEND_LANGUAGE=csharp):**
- `cd backend && dotnet test --collect:"XPlat Code Coverage"`
- `cd backend && dotnet format --verify-no-changes`

**Frontend:**
- `cd frontend && npm run test`
- `cd frontend && vue-tsc --noEmit`
- `cd frontend && npm run lint`

**Mobile (when mobile/ exists):**
- `cd mobile && flutter test --coverage`
- `cd mobile && flutter analyze && dart format --set-exit-if-changed .`

### Scope Rules

- Each agent: single, clear responsibility
- No assumptions about other agents — pass explicit paths/interfaces
- If agent A writes a file agent B imports, A finishes first

### When NOT to Use

- Simple single-file edits
- Strict dependency chains
- Interactive decisions based on partial results
