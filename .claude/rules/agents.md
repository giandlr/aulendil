> **Mode-aware:** Sub-agent behavior adapts to the current mode (build or deploy). Read `.claude/mode` to determine which mode is active.

## Use Sub-Agents for Parallel Work

Claude Code can spawn sub-agents via the Task tool. Use them aggressively — they run
in parallel and cut total wall-clock time dramatically.

### Mode-aware validation

**Build mode:** After edits, run validation only if the user explicitly asks. Don't auto-run the full validation suite — it slows down the creative flow.

**Deploy mode:** After edits, always run the full parallel validation suite as currently defined.

### When to spawn sub-agents

**Always parallelize these:**

- Writing frontend code + backend code for the same feature (independent files, no shared state)
- Running tests + linting + type-checking after an edit (all read-only, fully independent)
- Scaffolding multiple files that do not import each other (e.g., model + service + route + test)
- Reading/exploring multiple unrelated parts of the codebase to gather context

**Examples:**

```
// Bad — sequential
1. Write backend route
2. Write backend test
3. Write frontend service
4. Write frontend component
5. Run pytest
6. Run vitest
7. Run vue-tsc

// Good — parallel sub-agents
Agent 1: Write backend route + backend test
Agent 2: Write frontend service + frontend component
[wait for both]
Agent 3: Run pytest
Agent 4: Run vitest + vue-tsc
```

### How to implement a full feature

1. **Plan first** — identify all files that need to change
2. **Split by layer** — backend agent (route + service + model + test) and frontend agent (service + component + store + test) in parallel
3. **Validate in parallel** — after both agents finish, spawn one agent per check: pytest, vitest, vue-tsc, ruff+mypy
4. **Fix in parallel** — if multiple files have errors, fix them with separate agents

### Running validation commands in parallel

After writing or editing code, always run these as parallel sub-agents:

| Agent | Command |
|-------|---------|
| backend-test | `cd backend && pytest --cov --cov-report=term-missing` |
| frontend-test | `cd frontend && npm run test` |
| frontend-types | `cd frontend && vue-tsc --noEmit` |
| backend-lint | `cd backend && ruff check . && mypy .` |
| frontend-lint | `cd frontend && npm run lint` |

Never run these sequentially. Always run them together and collect results.

### Sub-agent scope rules

- Each sub-agent should have a **single, clearly defined responsibility**
- Sub-agents must not make assumptions about what other agents are doing — pass explicit file paths and expected interfaces
- If a sub-agent writes a file that another sub-agent imports, the writing agent must finish first
- Merge results in the main context after all agents complete

### When NOT to use sub-agents

- Simple single-file edits (not worth the overhead)
- When one task strictly depends on the output of another (e.g., migration must run before seeding)
- When you need to interactively decide the next step based on partial results
