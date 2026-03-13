You are a Staff Platform Engineer and AI Tooling Architect. Your task is to design
and output a COMPLETE, PRODUCTION-READY Claude Code governance and autonomous CI/CD
system. Every file must be fully written — no placeholders, no "add your logic here",
no truncation. This system will be used by non-technical product managers who have
zero coding knowledge. They will only interact with Claude Code in natural language.
The system must silently enforce all engineering best practices on their behalf.

═══════════════════════════════════════════════════════════
CONTEXT & CONSTRAINTS
═══════════════════════════════════════════════════════════

- Development agent: Claude Sonnet (claude-sonnet-4-6) — builds the code
- Review agent: Claude Opus 4.6 (claude-opus-4-6) — reviews the code
- The Opus reviewer must be spawned as a completely ISOLATED process with:
    claude -p --model claude-opus-4-6 --system-prompt-file [file]
  It must receive ZERO context from the development session — no CLAUDE.md
  injection, no conversation history, no session memory. It only sees:
  (a) its reviewer system prompt and (b) a structured review payload containing
  the git diff, test results, and coverage data.
- All hook scripts must be bash, fully executable, and production-safe
- The system targets Node.js/TypeScript projects primarily, with Python as secondary
- Non-technical users must never need to touch any of these files

═══════════════════════════════════════════════════════════
TECH STACK REFERENCE
═══════════════════════════════════════════════════════════

All stack-specific decisions — which linters to run, which test frameworks
to invoke, which import patterns to enforce, which ORM conventions to follow —
must be derived from reading docs/tech-stack.md before generating any file.

Do not hardcode stack assumptions into hooks, agents, or rules. Instead:
  - Hook scripts must check the RUNTIME field to know which linter/formatter
    to invoke (eslint for JS/TS, ruff for Python, etc.)
  - Agent system prompts must reference the frameworks listed in tech-stack.md
    when describing how to run tests, how to connect to the DB, etc.
  - The CLAUDE.md project template must have its Tech Stack section
    pre-populated from tech-stack.md values
  - The sprout-init.sh setup script must read tech-stack.md to decide which
    tools to install

Read docs/tech-stack.md as the first action before generating any output.
If a field in tech-stack.md conflicts with an assumption you would otherwise
make, tech-stack.md always wins.

═══════════════════════════════════════════════════════════
ORCHESTRATION PRINCIPLE — NON-NEGOTIABLE
═══════════════════════════════════════════════════════════

The master/orchestrator agent is a PURE COORDINATOR. It never writes code,
never edits files, never runs tests directly, and never reads source files
itself. Its only job is to:
  1. Decompose the task into discrete units of work
  2. Assign each unit to the appropriate subagent via the Task tool
  3. Receive summarized results back from subagents
  4. Make gate decisions based on those results
  5. Report final status to the user

If the master agent finds itself about to use Write, Edit, Bash, or Read on
a source file, it must STOP and instead spawn a subagent to do that work.

This separation is enforced at the agent definition level:
  - Master/orchestrator agents: tools restricted to Task, Bash (scripts only),
    Read (logs and results only)
  - Worker subagents: tools scoped to what their specific job requires

The purpose of this constraint is context efficiency, parallelism, and
accountability. Each subagent brings a clean, focused context window to its
task. The orchestrator never pollutes its context with implementation details
— it stays high-level so it can coordinate across many parallel workers
without hitting context limits.

═══════════════════════════════════════════════════════════
LAYER 1 — MEMORY FILES (CLAUDE.md HIERARCHY)
═══════════════════════════════════════════════════════════

Output the following files in full:

1. ~/.claude/CLAUDE.md  (Global — applies to ALL projects on the machine)
   Must cover:
   - Why rules exist (intent and reasoning), not just what the rules are
   - Security philosophy (OWASP Top 10 reasoning, not just a list)
   - Code quality intent (SOLID, DRY, KISS — explained simply)
   - What to do when a hook blocks an action
   - Test-writing philosophy
   - How to interpret pipeline failures
   - Keep under 100 lines. Bullet points only. No headers beyond H2.

2. CLAUDE.md  (Project root — applies to this specific project)
   Must be a TEMPLATE with clearly marked placeholders for:
   - App name and one-sentence purpose
   - Tech stack
   - Project directory structure with explanations of each folder's purpose
   - How to run, test, lint, and migrate
   - Key architectural rules specific to this project
   - "Build Mode Behavior" section: instructions for how Claude narrates its
     work in plain English during build mode. Claude must explain what it did
     and why in friendly, non-technical language after each significant action.
     Example: "I added a loading spinner so users see something while data
     loads." Never mention tool names, linter names, or technical jargon
     to the user.
   - "Deploy Mode Behavior" section: instructions for how Claude handles the
     deploy pipeline. Must reference the gate level selection (mvp/team/
     production) and explain that Claude asks the user which level to target
     using plain English business questions like "Is this just for you to
     test, for your team to use, or for external users?"
   - Simplified "Definition of Done" that references gate levels instead of
     a monolithic checklist:
       * BUILD mode: code works, no security issues, tests exist
       * DEPLOY (mvp): security scan passes, app starts, happy path works
       * DEPLOY (team): tests pass (60% coverage), auth works, errors handled
       * DEPLOY (production): full test suite (80%+ coverage), performance
         validated, Opus review approved, all Tier 1 enterprise features
   - "Plain English Language Rules" section: Claude must never mention tool
     names (ESLint, ruff, mypy, bandit, gitleaks, Vitest, pytest, Playwright)
     to the user. Instead, say what the tool does: "I checked for security
     issues" not "I ran gitleaks." "I verified the code has no errors" not
     "I ran ESLint and mypy." Technical tool names may appear in logs and
     audit trails, but never in conversational output to the user.
   Keep under 100 lines.

3. .claude/rules/api.md  (Loaded when touching routes/controllers)
   - Response envelope shape
   - Zod/Joi validation requirement
   - Pagination rules
   - HTTP status code guide
   - Error handling: never expose stack traces, always log server-side with
     correlation ID

4. .claude/rules/auth.md  (Loaded when touching auth/middleware)
   - JWT: verify signature AND expiry, never skip
   - Refresh token storage (hashed in DB)
   - Password hashing (bcrypt, min rounds 12)
   - Session invalidation on logout
   - Uniform error messages (no user enumeration)
   - RBAC: server-side check on every request

5. .claude/rules/database.md  (Loaded when touching models/migrations/queries)
   - Migrations only, never ALTER TABLE in app code
   - Required columns on every table
   - Soft deletes only
   - Index requirements
   - N+1 query ban
   - Transactions for multi-step writes
   - Never SELECT *

6. .claude/rules/frontend.md  (Loaded when touching UI components)
   - No raw API calls in components (must go through service layer)
   - Loading/error/empty states required for every async operation
   - Accessibility: aria labels, keyboard nav, color contrast
   - No inline styles except dynamic values
   - Component size limit

═══════════════════════════════════════════════════════════
LAYER 2 — HOOKS (DETERMINISTIC ENFORCEMENT)
═══════════════════════════════════════════════════════════

Output .claude/settings.json in full, wiring ALL hooks to ALL scripts.

Then output each script in full:

7. .claude/hooks/pre-write-guard.sh  (PreToolUse: Write|Edit|MultiEdit)
   Must BLOCK (exit 2) on:
   - Writing to .env*, *.pem, *.key, id_rsa, credentials* paths
   - Hardcoded secrets matching: password=, secret=, api_key=, AWS access key
     pattern (AKIA...), OpenAI/Anthropic key patterns (sk-...), raw JWTs
   - String-concatenated SQL queries (injection risk)
   - eval() usage in JS/TS
   Must WARN (stderr, exit 0) on:
   - More than 2 TODO/FIXME markers in a single file
   Must LOG every write attempt to .claude/audit.log with timestamp and filepath

8. .claude/hooks/pre-bash-guard.sh  (PreToolUse: Bash)
   Must BLOCK (exit 2) on:
   - rm -rf / or rm -rf ~
   - Any DROP TABLE, DROP DATABASE, TRUNCATE, DELETE FROM WHERE 1
   - git push --force to main or master
   - chmod -R 777
   - dd if= commands
   Must WARN on:
   - npm install or pip install without saving to lockfile
   - Any curl | bash patterns
   Must LOG every bash command to .claude/audit.log

9. .claude/hooks/post-edit-enforce.sh  (PostToolUse: Write|Edit|MultiEdit)
   Must be MODE-AWARE (reads .claude/mode):
   - BUILD mode: Only BLOCK on security issues (gitleaks secrets, service role
     key in frontend, direct Supabase calls outside services/). All other
     checks are logged to audit.log but DO NOT block. Quality enforcement
     moves to CLAUDE.md instructions — Claude auto-fixes quality issues and
     narrates what it did in plain English.
   - DEPLOY mode: Full enforcement as described below (all linters, type
     checks, enterprise checks) with plain English error messages:
     For .ts/.tsx/.js/.jsx files:
     - Run ESLint with --max-warnings=0 (BLOCK on failure)
     - Run tsc --noEmit (BLOCK on type errors)
     - Detect console.log/debug left in code (WARN)
     - Run the corresponding test file if it exists
     For .py files:
     - Run ruff check and ruff format
     - Run bandit security scan (BLOCK on HIGH severity)
     - Run mypy type check (BLOCK on errors)
     - Check for bare except: clauses (BLOCK)
     For all files:
     - Run gitleaks if available (BLOCK on secrets found)
   Exit 2 on any BLOCK condition, with a clear message telling Claude what
   to fix.
   All error messages must be plain English. Never expose tool names (ESLint,
   ruff, mypy, bandit) to the user — describe what the check does instead.

10. .claude/hooks/stop-final-audit.sh  (Stop event)
    Must be MODE-AWARE:
    - BUILD mode: Only run gitleaks. Skip npm audit, pip-audit, TODO check.
    - DEPLOY mode: Full current behavior:
      - Full gitleaks scan across working directory
      - npm audit --audit-level=high (warn only)
      - pip-audit if requirements.txt exists (warn only)
      - Count TODO/FIXME across all git-tracked changed files (warn if > 0)
      - Check that every new source file (from git diff --diff-filter=A) has a
        corresponding test file — warn for each missing one
    - Write final audit summary to .claude/audit.log
    - Exit 0 (warn but never block at Stop stage — too late to undo)
    All error messages must be plain English. Never expose tool names (ESLint,
    ruff, mypy, bandit) to the user.

NEW: .claude/hooks/lib/mode.sh — shared helper sourced by all hooks:
    - get_mode(): reads .claude/mode file, returns "build" or "deploy"
      (defaults to "build" if file missing)
    - friendly_block(): wraps exit-2 messages in plain English, never
      exposing tool names
    - log_audit(): appends timestamped entries to .claude/audit.log

NEW: .claude/mode — runtime mode flag file. Contains either "build" or
    "deploy". Defaults to "build". Changed to "deploy" during the deploy
    pipeline, then reset to "build" after pipeline completes.

═══════════════════════════════════════════════════════════
LAYER 3 — SUBAGENTS
═══════════════════════════════════════════════════════════

Output each agent file in full including YAML frontmatter and complete system prompt:

11. .claude/agents/tdd-enforcer.md
    model: sonnet
    tools: Read, Write, Edit, Bash, Glob
    Purpose: Enforces Red->Green->Refactor TDD cycle. Blocks any implementation
    code from being written before a failing test exists for that behavior.
    Must output a structured TDD STATUS block after each phase showing: current
    phase, test file, test name, test result (with FAILING being expected in Red),
    and next required action. Must refuse to proceed and explain why if the
    developer tries to skip writing the test first.
    Must be mode-aware:
    - BUILD mode: Write tests alongside code naturally without enforcing strict
      Red->Green->Refactor ordering. Tests are still required but the workflow
      is flexible — write implementation and tests in whatever order feels
      natural, as long as both exist when done.
    - DEPLOY mode (production gate): Enforce strict TDD cycle. Red phase must
      show a failing test before any implementation code is written.

12. .claude/agents/pipeline-orchestrator.md
    model: sonnet
    tools: Task, Bash (restricted to reading log files and invoking pipeline
    scripts only — NOT for running tests directly), Read (restricted to
    .claude/tmp/ result files only — NOT source files)

    Purpose: Pure orchestration only. This agent NEVER runs tests itself,
    NEVER reads source code, and NEVER writes or edits any file. Every
    discrete action is delegated via the Task tool to a specialist subagent.
    The orchestrator's sole responsibilities are:
      (a) spawn unit-test-runner, ui-test-runner, integration-runner, and
          perf-runner as parallel Task calls
      (b) wait for all four to complete
      (c) read their summarized result outputs from .claude/tmp/
      (d) apply the gate rule: all pass -> invoke Opus review script;
          any fail -> report and stop
      (e) write the final pipeline-results.md summary
    If this agent's reasoning leads it toward running a test command or
    reading a source file, it must instead spawn a subagent for that action.
    Must accept a gate level parameter (mvp/team/production). Read
    .claude/deploy-gates.json to determine which checks to run:
    - MVP: only spawn security scan + smoke test (skip unit-test-runner,
      ui-test-runner, integration-runner, perf-runner, Opus review)
    - Team: spawn unit-test-runner with relaxed coverage thresholds (60%
      line, 50% branch). Skip perf-runner and Opus review.
    - Production: spawn all runners with full thresholds. Run Opus review
      after all pass.
    Narrate progress in plain English: "Running security checks..." not
    "Invoking gitleaks scan." "Checking that tests pass..." not "Spawning
    unit-test-runner subagent."

13. .claude/agents/unit-test-runner.md
    model: sonnet
    tools: Bash, Read
    Purpose: Runs the full unit test suite (Jest/Vitest for TS, pytest for Python).
    Reports: total, passed, failed (with file:line for each failure), skipped,
    line coverage %, branch coverage %. PASS criteria: zero failures, zero skipped
    in new code, >= 80% line coverage, >= 70% branch coverage.

14. .claude/agents/ui-test-runner.md
    model: sonnet
    tools: Bash, Read
    Purpose: Runs Playwright or Cypress end-to-end tests. Pre-flight checks that
    the app is running on localhost before starting. Reports: total scenarios,
    passed, failed (with screenshot path if available), flaky (passed on retry),
    accessibility violations. PASS criteria: zero failures, all critical user
    flows covered.

15. .claude/agents/integration-runner.md
    model: sonnet
    tools: Bash, Read
    Purpose: Runs API and database integration tests. Resets test DB before run.
    Runs Pact contract tests if configured. Reports: endpoints tested, passed,
    failed (with method/path and expected vs actual), DB isolation status,
    contract test results. PASS criteria: zero failures, clean DB isolation.

16. .claude/agents/perf-runner.md
    model: sonnet
    tools: Bash, Read
    Purpose: Runs k6 load tests and Lighthouse frontend performance audits.
    Reports: API p50/p95/p99 latency, error rate, Lighthouse performance score,
    Lighthouse accessibility score. PASS thresholds: p95 < 500ms, p99 < 1000ms,
    error rate < 1%, Lighthouse performance >= 80, Lighthouse accessibility >= 90.

═══════════════════════════════════════════════════════════
PROGRESSIVE DEPLOY GATES
═══════════════════════════════════════════════════════════

Output .claude/deploy-gates.json defining three progressive gate levels:

  "mvp": Quick validation for personal testing
    - Security scan (gitleaks)
    - App starts without errors
    - One happy path works
    - No coverage requirements

  "team": Validation for sharing with colleagues
    - Everything in MVP
    - Unit tests pass (60% line coverage, 50% branch)
    - Basic error handling present
    - Authentication works
    - Skip performance tests and Opus review

  "production": Full validation for external/company-wide use
    - Everything in Team
    - Full test suite (80% line, 70% branch)
    - Integration tests and e2e tests
    - Performance tests (p95 <500ms)
    - Opus code review
    - All Tier 1 enterprise features present

The pipeline orchestrator reads this file to determine which checks to run
at each gate level. This replaces the all-or-nothing approach with progressive
enforcement that scales with project maturity.

═══════════════════════════════════════════════════════════
ACCESS PATTERNS
═══════════════════════════════════════════════════════════

The system must support two access patterns:

1. Internal-only (default): All users authenticate via company SSO or
   Supabase Auth. Standard RBAC with Admin/Manager/Member/Viewer roles.

2. Dual-portal (internal + external): When the manager mentions external
   users (suppliers, customers, partners), Claude scaffolds:
   - /app/* routes for internal users (company SSO, full features)
   - /portal/* routes for external users (invite-only, limited views)
   - Separate RLS policies scoped to organization/tenant
   - External user role with minimal permissions
   - Stricter rate limiting on external endpoints

   Document this pattern in docs/architecture.md and docs/tech-stack.md.

═══════════════════════════════════════════════════════════
LAYER 4 — OPUS REVIEWER (ISOLATED CONTEXT)
═══════════════════════════════════════════════════════════

17. .claude/reviewers/opus-system-prompt.md
    This is the ONLY context Opus receives. It must:
    - Establish the adversarial reviewer role clearly
    - Explicitly state that Opus has NO knowledge of what was built, by whom,
      or what decisions were made — and that this is intentional
    - Define BLOCKING issues (must fix before merge): security vulnerabilities,
      logic errors not caught by tests, missing coverage on critical paths,
      N+1 queries, SOLID violations causing maintenance pain, race conditions,
      missing transaction boundaries, broken API contracts, missing input
      validation, improper error handling
    - Define ADVISORY issues (should fix, not blocking): readability, naming,
      missing comments on non-obvious logic, architectural concerns, test quality,
      dead code, style inconsistencies
    - Define the EXACT output format Opus must use, including:
      * Header with files reviewed and commit range
      * BLOCKING ISSUES section with: issue ID, category, title, file:line,
        problematic code snippet (max 5 lines), precise problem explanation,
        concrete fix recommendation
      * ADVISORY ISSUES section with same structure
      * SUMMARY block with: blocker count, advisory count, Gate decision
        (APPROVED or CHANGES REQUIRED), confidence level
      * POSITIVE OBSERVATIONS section (required, not optional)
    - Instruct Opus to never summarize what the code does, never explain its
      reasoning process, go directly to findings

18. .claude/scripts/build-review-payload.sh
    Constructs the structured review package that Opus receives. Must include:
    - git diff HEAD~1..HEAD --stat (changed files summary)
    - git diff HEAD~1..HEAD (full diff)
    - Contents of .claude/tmp/unit-results.json (truncated to 100 lines)
    - Contents of .claude/tmp/ui-results.json (truncated to 100 lines)
    - Contents of .claude/tmp/integration-results.json (truncated to 100 lines)
    - Contents of .claude/tmp/k6-summary.json if exists
    - Coverage summary parsed from coverage.json
    Output to .claude/tmp/review-payload.md

19. .claude/scripts/invoke-opus-reviewer.sh
    Must use EXACTLY this invocation pattern:
      claude -p \
        --model claude-opus-4-6 \
        --system-prompt-file .claude/reviewers/opus-system-prompt.md \
        --allowedTools "Read,Glob,Grep,Bash" \
        "Please review the following code changes:\n\n$(cat .claude/tmp/review-payload.md)"
    No --continue. No --resume. No session flags. Completely fresh context.
    Parse the Gate decision from output. Exit 2 if CHANGES REQUIRED or if
    blocker count > 0. Save output to .claude/tmp/opus-review-[timestamp].md.
    Print the full review to stdout so it appears in the pipeline log.

20. .claude/scripts/run-pipeline.sh
    The master orchestrator triggered by the Stop hook. Must:
    - Create .claude/tmp/ if it doesn't exist
    - Run stages 1-4 (unit, ui, integration, performance) IN PARALLEL using
      background jobs (&) with wait to collect results
    - Track which stages failed in a FAILED_STAGES array
    - Gate: if any test stage failed, skip Opus review, report what failed, exit 1
    - If all test stages passed: call invoke-opus-reviewer.sh
    - Print a formatted final report with: stage results, total duration,
      overall gate decision (PIPELINE PASSED / PIPELINE FAILED)
    - Exit 0 only if all stages including Opus review passed

═══════════════════════════════════════════════════════════
LAYER 5 — SETUP AND DOCUMENTATION
═══════════════════════════════════════════════════════════

21. scripts/sprout-bootstrap.sh  (Full project scaffolding + start script)
    Replaces sprout-init.sh as the single entry point for new projects.
    Must:
    Phase 1 — Scaffold:
    - npx nuxi init frontend (Nuxt 3 with TypeScript)
    - Create backend/ with main.py (FastAPI app), requirements.txt
    - Create supabase/ dir
    - Create full directory structure:
      frontend/{components,composables,pages,stores,services,types,tests}
      backend/{routes,services,models,middleware,tests}
      supabase/migrations/
    Phase 2 — Configure:
    - frontend: install tailwindcss, pinia, vee-validate, zod, @supabase/supabase-js
    - frontend: create nuxt.config.ts with tailwind + supabase modules
    - frontend: create base layout (app.vue with nav shell)
    - backend: create venv, pip install fastapi uvicorn supabase python-dotenv
    - backend: install dev tools (ruff, mypy, bandit, pip-audit, pytest, pytest-cov, httpx)
    - backend: create base middleware (auth.py, error_handler.py, cors.py)
    Phase 3 — Supabase:
    - supabase init (if not already initialized)
    - supabase start (local Docker containers)
    - Extract local Supabase credentials from supabase status
    - Write .env.local with SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
    Phase 4 — Start:
    - Start backend: uvicorn in background
    - Start frontend: npm run dev in background
    - Wait for both to be healthy
    - Print: "Your app is running at http://localhost:3000"
    Phase 5 — Dev tools (absorbed from sprout-init.sh):
    - Install gitleaks, k6 if missing
    - Install eslint, prettier, vue-tsc
    - chmod +x all scripts

    scripts/sprout-init.sh is kept as a deprecated wrapper that redirects
    to sprout-bootstrap.sh but still works for backwards compatibility.

22. docs/architecture.md  (Reference doc Claude loads on demand)
    A template covering: system overview, technology decisions and their
    rationale, key data flows, external dependencies, environment variables
    required, local development setup, deployment architecture

23. docs/api-conventions.md  (Reference doc Claude loads on demand)
    Covers: request/response envelope format with examples, authentication
    headers, error response format with error code catalogue, versioning
    strategy, pagination format, rate limiting headers

24. docs/done-checklist.md  (Reference doc for Definition of Done)
    A markdown checkbox list covering: tests passing, no lint errors, no
    type errors, no hardcoded secrets, error handling on all async ops,
    input validation on all user-supplied data, OWASP review done,
    test file exists for every new source file, no TODO/FIXME left,
    Opus review APPROVED

═══════════════════════════════════════════════════════════
OUTPUT REQUIREMENTS
═══════════════════════════════════════════════════════════

- Output EVERY file in full. No truncation. No "..." placeholders.
- Use fenced code blocks with the correct language tag for each file.
  Shell scripts: ```bash, JSON: ```json, Markdown: ```markdown, YAML: ```yaml
- Label each file clearly with its full path before the code block.
- Scripts must be production-safe: use set -euo pipefail where appropriate,
  handle missing commands gracefully (command -v checks), never assume tools
  are installed without checking first.
- All exit codes must be used correctly: exit 0 (pass/warn), exit 1 (error),
  exit 2 (block Claude from proceeding).
- After all files, output a DIRECTORY TREE showing the complete structure.
- After the directory tree, output a FLOW DIAGRAM in ASCII or Mermaid showing
  how a single feature request flows from manager input -> TDD -> development
  -> hooks -> pipeline -> Opus review -> final gate decision.
- Finally, output a QUICK REFERENCE CARD (max 30 lines) that a non-technical
  manager can read to understand: what Claude Code will do automatically, what
  the pipeline stages are, what it means when something is blocked, and what
  the Opus review is.
- For EVERY agent file, the tools: field in the YAML frontmatter must be
  explicitly and minimally scoped. No agent should have tools it doesn't
  need for its specific job. The orchestrator must list Task as its primary
  tool. Worker agents must NOT have Task (they don't spawn further agents —
  only the orchestrator spawns). This enforces a strict two-tier hierarchy:
  orchestrators coordinate, workers execute.

Do not ask clarifying questions. Do not summarize what you are about to do.
Begin immediately with File 1.
