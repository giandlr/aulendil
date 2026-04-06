# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** This file is auto-maintained by the Claude Code pipeline.
> Entries are added automatically when the pipeline passes.
> Manual edits to the Unreleased section will be overwritten on the next
> pipeline run. To add human commentary, use release notes when tagging
> a version with `.claude/scripts/tag-release.sh`.

## [Unreleased]
<!-- UNRELEASED_INSERT_POINT -->

## [v1.7.4] — 2026-04-06

### Added
- **Discovery outputs `.claude/BASELINE.md`:** Discovery now explicitly creates a persistent baseline feature checklist alongside `brief.md`. Build mode checks this file before every feature and marks items `[x]` as they are completed — the baseline tracking system that was specified but never actually generated now works.
- **Scope change flow:** When a user expands the audience mid-project (e.g., "my team will use this now"), the baseline checklist is re-presented for the new audience level and `BASELINE.md` is updated with any newly required features.
- **Mobile Discovery follow-up:** When mobile is selected, Discovery now asks a follow-up: "Any mobile-specific needs?" (offline support / push notifications / camera or GPS / none).
- **Design direction in Discovery:** Discovery now asks about aesthetic preferences and offers 3 fallback directions (Modern editorial, Warm minimal, Bold industrial) when the user has no preference. Recorded in `brief.md` for consistent styling across all components.
- **"Other" app type features:** Discovery Round 2 now provides a generic feature list (CRUD, search, file upload, notifications, reports, approval workflows, calendar) when the user picks "other" app type.
- **Expanded Tier 1 pipeline checks:** `tier1-enterprise` stage now checks for RBAC middleware, rate limiting, error pages, form validation (vee-validate/zod), and CORS wildcard — up from 3 checks to 8.
- **Coverage threshold validation:** Pipeline now reads coverage thresholds from `deploy-gates.json` and fails with a numeric comparison if actual coverage is below required percentage.
- **Mobile CI/CD stage:** Pipeline now runs `flutter test` + `flutter analyze` when `mobile/` exists — previously mobile code was never validated at deploy time.
- **Dependency vulnerability scanning in pipeline:** `npm audit` and `pip-audit` now run as part of the security scan stage at team+ gates, blocking on high/critical vulnerabilities — previously these only ran in the stop hook (which never blocked).
- **Enterprise context in Opus review payload:** `build-review-payload.sh` now includes `BASELINE.md`, `brief.md`, Tier 1 results, security scan output, and backend test results so the Opus reviewer can advise on missing enterprise features.
- **Migration push in deploy scripts:** `deploy-cloud.sh` and `deploy-azure.sh` now run `supabase db push` before deploying — previously apps could deploy with code referencing tables that didn't exist.
- **First-user Admin bootstrap recipe:** `baseline-recipes.md` now includes a SQL trigger (`bootstrap_first_admin()`) that assigns Admin role to the first user when `user_roles` is empty.
- **Pre-build environment check:** `agents.md` now requires verifying dependencies are installed before writing code. Detects stack mismatches (Python backend but `.env` says C#) and prompts for bootstrap.
- **Escalation guidance:** When validation fails due to infrastructure (Docker not running, Supabase connection refused), agents now explain the issue and ask the user to fix the environment instead of looping.
- **Deploy target conflict detection:** When switching `DEPLOY_TARGET`, the system now warns about residual config files from the previous target and asks before cleaning up.
- **Playwright E2E in post-feature validation:** `agents.md` now includes `npx playwright test` in the mandatory post-feature validation commands when Playwright is configured and the feature touches UI.

### Changed
- **RBAC check searches by content, not filename:** Pipeline Tier 1 check now greps for `CREATE TABLE roles` + `CREATE TABLE user_roles` instead of checking for hardcoded filename `00000000000001_rbac.sql`.
- **Frontend design rules reconciled with TailwindCSS:** Spatial composition and backgrounds sections rewritten to use Tailwind-achievable techniques. `<style scoped>` now explicitly allowed for effects Tailwind can't express (animations, SVG backgrounds, gradient meshes). "One unforgettable detail" replaced with concrete: "one distinctive visual element per page."
- **Fallback design directions defined:** Three pre-built aesthetic options (Modern editorial with Playfair Display, Warm minimal with Nunito, Bold industrial with JetBrains Mono) replace the vague "pick a tone" instruction.

### Fixed
- **Bootstrap stack mismatch on resume:** Bootstrap now detects when `backend/` was scaffolded for Python but `.env` says `BACKEND_LANGUAGE=csharp` (or vice versa) and warns instead of silently skipping re-scaffold.

## [v1.7.3] — 2026-03-22

### Fixed
- **Multi-project database isolation:** Every project now gets a unique Supabase `project_id` and isolated port block (API, DB, Studio, Inbucket) written into `supabase/config.toml` before `supabase start` runs. Previously, all projects used the same default ports (54321–54324), so bootstrapping a second app would conflict with — and potentially overwrite or corrupt — an existing running project's database. A global port registry at `~/.aulendil/port-registry` tracks assignments across projects (e.g. project 1 = 54321, project 2 = 54421), ensuring each app's Docker containers are completely isolated. The fix is idempotent: re-running bootstrap on an existing project reuses its registered ports.

## [v1.7.2] — 2026-03-18

### Fixed
- **Database data preserved during backend changes:** `.claude/rules/database.md` previously said "Test with `supabase db reset` before pushing", giving Claude implicit permission to wipe all data when testing migrations. Replaced with an explicit prohibition: always apply forward with `supabase db push`; `supabase db reset` only if the user explicitly asks.
- **Hook blocks `supabase db reset`:** `pre-bash-guard.sh` now blocks `supabase db reset` at the hook level with a plain-English message, the same way DROP TABLE and TRUNCATE are blocked.

## [v1.7.1] — 2026-03-18

### Changed
- **Frontend design quality (always-on):** `.claude/rules/frontend.md` now embeds the full set of production design principles — typography, colour, motion, spatial composition, depth, and a hard NEVER list — directly in the rule file. Because `frontend.md` has a `globs` header scoped to all frontend files, these principles are automatically in context whenever Claude touches any page, component, composable, or store. No skill invocation required.
- **Workflow rule simplified:** Build Mode's frontend-design note updated to remove the "invoke the skill" instruction; it now says: ask one brand question at project start, commit to a bold visual direction, then apply it consistently across all components.

## [v1.7.0] — 2026-03-17

### Added
- **`check-gate.sh`:** New script for quick gate readiness checks before deploying — tells you exactly what's missing for your chosen gate level without running the full pipeline.
- **`preflight-check.sh`:** Validates bootstrap prerequisites (Node, Python, Docker, etc.) before running bootstrap, with clear actionable error messages.
- **Bootstrap checkpoint/resume:** Bootstrap tracks completed phases in `.claude/bootstrap-state`; on re-run it skips completed phases and picks up where it left off. Use `--fresh` to start over.
- **Docker-optional bootstrap:** Phase 3 now detects Docker availability and continues without Supabase if Docker isn't running. The app scaffolds fully and a placeholder `.env` is written.
- **Tier 1 enterprise feature check stage:** `run-pipeline.sh` now runs a `tier1-enterprise` stage at Production gate that checks for RBAC migration, GET /health endpoint, and RLS on all migration tables.
- **Five new C# backend rule sections:** Rate limiting, Azure RLS, JWT verification detail, idempotency, and service role key handling added to `.claude/rules/csharp-backend.md`.
- **Debug mode:** Both `run-pipeline.sh` and `bootstrap.sh` now activate `set -x` when `AULENDIL_DEBUG=1` is set.
- **`.claude/refs/` directory:** On-demand reference docs (mobile, C#, Discovery, Deploy, Session, baseline recipes) moved out of auto-loaded rules to reduce context overhead by 35%.

### Changed
- **RBAC check now blocks deploys:** Was warn-only after the gate decision; now fails the pipeline at Team and Production gates if RBAC files are missing. Also detects C# RBAC middleware (`backend/Middleware/RbacMiddleware.cs`).
- **Schema isolation check now fails production gate:** Previously always exited 0 (warn only); now exits 1 at Production gate when schema issues are found.
- **Pipeline wait loop is data-driven:** Replaced fixed `for stage in security smoke unit...` loop with `SPAWNED_STAGES` array — only stages that were actually launched are waited on.
- **Opus reviewer hardened:** Payload build failure now short-circuits Opus with `PAYLOAD_ERROR` status; gate parsing uses structured fallback to `CHANGES_REQUIRED` on unexpected output.
- **Azure deploy hardened:** Readiness polling replaces `sleep 15`; migration check blocks production deploys without DB config; deploy-state.json validated after write; service role key leak check before Vercel deploy.
- **`setup-azure-db.sh` SQL parameterized:** Switched to quoted heredoc + sed substitution — no arbitrary bash expansion in SQL strings.
- **`deploy-azure.sh` env parsing safe:** Auth tokens suppressed from ACR login logs; env file parsed without `eval`.
- **Deploy gates cleaned up:** Removed phantom stages (`docker-test`, `azure-deploy`, `smoke-test-production`) that were listed in gate requires but never implemented in the pipeline script.
- **Discovery Mode simplified:** Round 1 reduced to 2 questions; baseline checklist is tiered by audience (just-me / team / external) rather than a single flat list.
- **Clarification rules tightened:** Added explicit skip conditions for trivially obvious tasks; added contextual validation narration.
- **`production-baseline.md`:** Baseline checklist and audience table brought into sync (account lockout alignment); added Tier/audience precedence explanation.
- **`enterprise-features.md`:** Replaced all `integration-runner` references; added C# sections for rate limiting, Azure RLS, JWT, idempotency, service role key.
- **Context optimization (-35% tokens):** Moved detailed specs (mobile, C#, Discovery, Deploy, Session, baseline recipes) from auto-loaded `.claude/rules/` to on-demand `.claude/refs/`. Rules now contain compact stubs with BLOCK rules; full specs read only when needed.
- **`post-edit-enforce.sh` optimized:** File content cached once (was read 8 times); early exit for non-code files (md, json, css, images); path checks use bash builtins instead of grep pipes.

### Fixed
- **Baseline checklist divergence:** Account lockout was listed as Required in the table but Offer in the checklist — both now consistent.
- **Perf URL hardcoded:** Lighthouse and curl now use `FRONTEND_URL` env var (defaults to `http://localhost:3000`) instead of the hardcoded value.
- **Schema grep false positives:** Word boundary added to `search_path` grep to prevent partial schema name matches.
- **Mode file collision:** `run-pipeline.sh` now writes `deploy:$$` (with PID) to `.claude/mode` to prevent concurrent pipeline runs from clobbering each other.

## [v1.6.0] — 2026-03-17

### Added
- **Production baseline rule:** `.claude/rules/production-baseline.md` — defines the minimum feature set every real app needs, mapped by audience type. Covers: forgot password, email verification, user management page (list, deactivate, role assignment), invite flow, account settings, and first-user admin bootstrap. Includes exact implementation spec for each feature so Claude knows what to build, not just that it should exist.
- **Discovery Mode baseline checklist:** Round 2 now presents applicable baseline features as a yes/no checklist via AskUserQuestion, framed as "things users almost always expect." For team/external apps this always includes forgot password, user management, role assignment, and user deactivation. Never skipped even when Discovery fast-paths.
- **Clarify before building:** Build Mode now requires 1–2 focused clarification questions via AskUserQuestion before starting any new feature. Questions cover: who can perform the action, edge case behavior, and UI preference. Only skipped for trivially obvious tasks.
- **Post-first-feature baseline check:** After the first substantive feature in a new project, Build Mode checks whether baseline features have been built and flags any gaps in plain English, offering to add them before continuing.
- **Integration test scaffold:** Bootstrap now creates `backend/tests/integration/` with a `conftest.py` (FastAPI TestClient fixture) and `test_api_health.py` (GET /health smoke test) so integration tests always exist and the pipeline stage never SKIPs on a fresh project.
- **k6 load test scaffold:** Bootstrap now creates `frontend/tests/k6/load-test.js` (1 VU, 10 iterations against `/health`) so the performance stage always has a script to run.
- **App seed placeholder:** Bootstrap Phase 1 creates `supabase/seed-app.sql` with a placeholder comment. Phase 3 runs it automatically if it contains any non-comment content — Claude populates it during Build.
- **SETUP.md:** Bootstrap Phase 2 now writes a `SETUP.md` to the project root with the full first-run sequence (start Supabase, push migrations, seed, start backend, start frontend) and all service URLs and the dev login. Useful on re-clone or after a break.

### Changed
- **Pipeline always runs full test suite:** MVP and Team gates no longer skip unit tests, integration tests, or UI tests. All gates run security scan + smoke + unit + integration + UI tests. Performance remains Production-only. Opus review runs at Team and Production. Gate levels still control coverage thresholds and deployment targets.
- **MVP gate coverage:** Line ≥ 60%, branch ≥ 50% (was null).
- **Opus review now runs at Team gate:** Was Production-only; now Team and Production both require Opus to pass.
- **UI tests no longer skip when app not pre-running:** The HTTP 000 pre-check was removed from `run-pipeline.sh`; Playwright's `webServer` config starts the app automatically.
- **Dead gate config removed:** `basic-error-handling` and `auth-works` entries removed from Team gate `requires` — these had no implementation in `run-pipeline.sh` and produced no output.
- **Discovery Mode Round 2:** Added production baseline checklist step; skip condition for fast-path no longer bypasses the baseline check for team/external apps.
- **Build Mode:** Added "Clarify before building" and "Production baseline" rules above the existing auto-include and validation rules.

### Fixed
- **Tailwind CSS never loaded:** `css: ["~/assets/css/main.css"]` was missing from the `nuxt.config.ts` heredoc in bootstrap. TailwindCSS v4 requires the explicit CSS entry; styles were silently dropped on every new project.
- **Nuxt DevTools blocked screenshots and production use:** `devtools: { enabled: true }` changed to `false`; DevTools injected a UI overlay that broke screenshot tests and caused confusion in production-like environments.
- **`.env` files could contain instruction text instead of real values:** Bootstrap now validates both `.env.local` and `frontend/.env` after writing them and warns (with a `WARNINGS[]` entry) if any value looks like a sentence rather than a scalar value.
- **Dev auth plugin swallowed Supabase failures silently:** The `if (!error)` branch only logged success; failures produced no output. Now logs `console.warn` with "is Supabase running? Start with: supabase start" when sign-in fails.

## [v1.5.0] — 2026-03-16

### Added
- **Framework updater:** `update.sh` — drop the new zip into an existing project, run `bash aulendil/update.sh`, and only framework-owned files are replaced. App code, `CLAUDE.md`, `.env`, and `.claude/mode` are never touched. Reports "Updated: v1.4.0 → v1.5.0" with a full list of what changed.
- **Version tracking:** `VERSION` file embedded in the zip; stamped to `.claude/version` on install and updated by `update.sh` — projects always know which framework version they are on.
- **Background server logs:** Bootstrap now starts backend and frontend in the background with output redirected to `logs/backend.log` and `logs/frontend.log`. Terminal is immediately usable after bootstrap. Summary screen shows `tail -f logs/backend.log` commands.
- **Stop script:** `scripts/stop.sh` — reads `.pids` and kills both servers cleanly. Replaces the hard-to-remember one-liner from the previous bootstrap summary.
- **Mandatory post-feature validation:** Build Mode now requires tests + lint + type-check after every feature implementation (not just at deploy time). Claude fixes all failures before responding — managers never see a broken state.

### Changed
- **`CLAUDE.md` is now project-only:** Reduced to 6 lines — just `[APP_NAME]` and an optional project notes section. All framework content (Tech Stack, Commands, Discovery Mode, Build Mode, Deploy Mode, Cloud Deploy Mode, Session Lifecycle, Definition of Done) moved to `.claude/rules/workflow.md`, which `update.sh` overwrites on every upgrade. Framework improvements now reach existing projects automatically.
- **`.claude/rules/workflow.md` (new):** Contains all content previously in the body of `CLAUDE.md`. Updated on every framework upgrade via `update.sh`.
- **`scripts/bootstrap.sh`:** Server startup section redirects output to `logs/`; summary shows log paths and `bash scripts/stop.sh` instead of the raw `kill` command. `logs/` added to `.gitignore` entries.
- **`.claude/rules/agents.md`:** Build Mode validation changed from "only if explicitly asked" to "mandatory after every feature". Fix loop now re-validates until clean before responding.

## [v1.4.0] — 2026-03-16

### Added
- **Flutter mobile option:** Discovery Mode now asks "Do you need a mobile app?" — selecting yes scaffolds a `mobile/` Flutter directory (iOS + Android) alongside the existing web frontend, sharing the same Supabase backend and API
- **Flutter stack:** Riverpod 2 (code-gen `@riverpod`) for state, `supabase_flutter` for auth/data, `go_router` for navigation, `flutter_test` + `mocktail` for testing — all enforced by `.claude/rules/mobile.md`
- **C# backend option:** Discovery Mode now asks "Which backend language?" — selecting C# scaffolds `backend/` as an ASP.NET Core 8 Minimal APIs project with EF Core 8 + Npgsql; works with both Vercel and Azure deploy targets
- **C# stack:** `Microsoft.AspNetCore.Authentication.JwtBearer` for Supabase JWT verification, `ApiResponse<T>` record type enforcing identical response envelope as Python stack, xUnit + Moq + `WebApplicationFactory` for testing — all enforced by `.claude/rules/csharp-backend.md`
- **C# scaffold script:** `.claude/scripts/scaffold-csharp-backend.sh` — creates full `backend/` directory structure via `dotnet new` and installs required NuGet packages
- **C# migration runner:** `.claude/scripts/setup-db-csharp.sh` — wraps `dotnet ef database update` and `dotnet ef migrations add`
- **C# Azure Dockerfile:** `scaffold-azure-configs.sh` now detects `BACKEND_LANGUAGE=csharp` and rewrites the Dockerfile to use `mcr.microsoft.com/dotnet/aspnet:8.0` runtime instead of Python
- **C# Azure deploy:** `deploy-azure.sh` runs `dotnet publish` before Docker build when `BACKEND_LANGUAGE=csharp`
- **Mobile rules:** `.claude/rules/mobile.md` — blocks Supabase calls outside `features/*/data/` and `setState` in Riverpod-driven screens; warns on screens over 200 lines
- **C# rules:** `.claude/rules/csharp-backend.md` — blocks raw SQL string concatenation, hardcoded secrets, and business logic in route handlers; warns on missing auth and xUnit tests without assertions
- **Mobile architecture doc:** `docs/mobile-architecture.md` — full Flutter architecture reference with auth flow, Realtime pattern, deployment (App Store / Google Play), and test strategy
- **BACKEND_LANGUAGE env var:** Written to `.env` at scaffold time; bootstrap reads it to branch between Python and C# scaffold paths
- **INCLUDE_MOBILE env var:** Written to `.env` at scaffold time; bootstrap reads it to scaffold the Flutter `mobile/` directory
- **Parallel validation:** `.claude/rules/agents.md` extended with C# validation commands (`dotnet test`, `dotnet format --verify-no-changes`) and mobile commands (`flutter test --coverage`, `flutter analyze`)
- **Manual updates:** 4 new slides (Flutter Mobile, Mobile Architecture, C# Backend Option, Choosing Your Stack); version 1.7, 30 slides total

### Changed
- **CLAUDE.md:** Discovery Mode Round 1 gains two new questions (mobile app? / backend language?); directory structure section adds mobile and C#-specific directories; commands section adds mobile and C# commands
- **docs/tech-stack.md:** Added `## Mobile` and `## Backend (C#)` sections; run commands, test commands, and code quality sections updated for all three stacks
- **docs/architecture.md:** Added C# Backend Architecture section (with system diagram) and Mobile Architecture section (with diagram) before the Azure deployment section
- **scripts/bootstrap.sh:** Reads `BACKEND_LANGUAGE` and `INCLUDE_MOBILE` from `.env`; branches to C# scaffold and Flutter scaffold when selected; Python path unchanged

## [v1.3.0] — 2026-03-14

### Added
- **Toolkit renamed to Aulendil:** "Managers' Agent Fleet" renamed to "Aulendil" (Quenya for "devoted to Aulë, the craftsman") across all files, docs, and the manual
- **Azure deployment target:** Four new scripts (`scaffold-azure-configs.sh`, `deploy-azure.sh`, `setup-azure-db.sh`, `generate-azure-handoff-doc.sh`) for deploying to Azure Container Apps
- **Google SSO via OAuth2 Proxy:** Employees log in with company email automatically — no extra accounts needed; dual-mode `get_current_user()` handles both Azure (X-Forwarded-Email) and Vercel (Supabase JWT) paths
- **Per-app schema isolation:** Each Azure app gets its own PostgreSQL schema (`APP_SCHEMA`) and Blob Storage container (`BLOB_CONTAINER`) on shared infrastructure
- **Azure deploy rule:** `.claude/rules/team-isolation.md` — blocks cross-schema queries, storage account key usage, and hardcoded container/schema names in Azure mode
- **Azure auth rules:** `.claude/rules/auth.md` extended with OAuth2 Proxy pattern, first-login user creation, dual-mode `get_current_user()`, email domain restriction via `AZURE_ALLOWED_EMAIL_DOMAIN`
- **Azure pipeline stages:** `run-pipeline.sh` now branches on `DEPLOY_TARGET` — common stages always run, then Vercel-specific or Azure-specific stages (schema-isolation-check, docker-build, docker-test, azure-deploy, smoke-test-production)
- **Azure gate config:** `deploy-gates.json` restructured to `{common, vercel, azure}` per gate level
- **Hook extensions:** `pre-write-guard.sh` detects embedded DB connection strings; `post-edit-enforce.sh` adds Azure-specific blocks (fires only when `DEPLOY_TARGET=azure`)
- **Deploy flow UX:** CLAUDE.md Deploy Mode now asks "company server or cloud?" if `DEPLOY_TARGET` unset; language rule: never say "Azure"/"Vercel" in conversation
- **Azure IT handoff doc:** Auto-generated `docs/azure-it-setup-guide.md` with resource group setup, Container Apps, PostgreSQL, Google OAuth client, OAuth2 Proxy config, VNet, Monitor alerts, DNS
- **Manual updates:** 4 new slides (deployment target comparison, Azure architecture, dual auth modes, app isolation); version 1.6, 26 slides total

### Changed
- **Script renames:** `sprout-bootstrap.sh` → `bootstrap.sh`, `sprout-init.sh` → `init.sh`, `sprout-guide.html` → `guide.html`, `sprout-logo-01.svg` → `logo-01.svg`
- **Dev user:** `dev@sprout.local` → `dev@aulendil.local`
- **PID file:** `.sprout-pids` → `.pids`
- **Docker tag:** `sprout-pipeline-check` → `pipeline-check`
- **Deploy state:** Added `azure` object alongside existing `cloud` (Vercel) object

## [v1.2.0] — 2026-03-14

### Added
- **Cloud deployment:** Four new scripts (`scaffold-cloud-configs.sh`, `deploy-cloud.sh`, `generate-handoff-doc.sh`, `setup-supabase-cloud.sh`) for deploying to Vercel + Supabase Cloud
- **Cloud Deploy Mode:** Discovery flow with three paths — self-service, IT handoff, and guided setup; triggered by "deploy to cloud", "make this live"
- **Vercel integration:** `vercel.json` with Nuxt 3 SSR + FastAPI serverless functions at `/api/*`; `api/index.py` adapter wraps existing backend with zero refactoring
- **IT handoff document:** Auto-generated `docs/deployment-guide.md` with Vercel setup, Supabase Cloud setup, env var mapping, security checklist, monitoring/rollback guide
- **CORS cloud support:** Dynamic origin list in `backend/main.py` reads `VERCEL_URL` and `PRODUCTION_URL` from environment
- **Security headers:** X-Content-Type-Options, X-Frame-Options, HSTS, Referrer-Policy configured in `vercel.json`
- **Playwright e2e testing:** Bootstrap installs `@playwright/test` + `@axe-core/playwright` with chromium-only for speed
- **Playwright config:** `frontend/playwright.config.ts` with sensible defaults — JSON reporter for CI, HTML for local, screenshots on failure, video on retry
- **Starter e2e tests:** Three test pattern files (`auth.spec.ts`, `smoke.spec.ts`, `forms.spec.ts`) in `frontend/tests/e2e/` — Claude adapts to actual app during build
- **Accessibility testing:** `@axe-core/playwright` integration in smoke tests for WCAG compliance checks
- **RBAC foundation:** `supabase/migrations/00000000000001_rbac.sql` creates `roles` and `user_roles` tables with 4 default roles (admin, manager, member, viewer)
- **RBAC middleware:** `backend/middleware/rbac.py` with `require_role()` FastAPI dependency for protected endpoints
- **useRole composable:** `frontend/composables/useRole.ts` with `hasRole()`, `isAdmin()`, `isManager()` for role-aware UI
- **RBAC RLS policies:** Row Level Security on `roles` (authenticated read, admin modify) and `user_roles` (own read, admin manage all) tables
- **Dev user admin role:** Bootstrap assigns admin role to `dev@aulendil.local` after RBAC migration
- **RBAC pipeline check:** Verifies `roles` table, RBAC middleware, and useRole composable exist at Team+ gates
- **GitHub Actions workflow:** Optional `deploy.yml` for CI/CD with Vercel (`--with-github-actions` flag)

### Changed
- **Deploy gates:** Team gate now requires `ui-tests` and `rbac-check`; all gates include `cloud` config section
- **Deploy state:** Added `cloud` object tracking provider, deploy URL, Supabase project ref
- **Pipeline:** Added RBAC verification stage and cloud deploy stage (triggered by `DEPLOY_TARGET=cloud`)
- **Bootstrap:** Now creates RBAC migration, middleware, composable, Playwright config, and starter tests
- **Architecture diagram:** Updated to show Vercel hosting both frontend SSR and FastAPI serverless
- **Tech stack:** Added hosting sections for Vercel and Supabase Cloud
- **Install script:** Copies cloud deployment scripts alongside existing toolkit files
- **Gitignore:** Added `.vercel/` and `.env.production`
- **Manual:** Added 2 new slides (Cloud Deployment, Roles & Permissions), updated to version 1.5 with 22 slides

## [v1.1.0] — 2026-03-14

### Added
- **Discovery mode:** Claude asks 2-3 rounds of clickable questions before building greenfield projects, producing a structured brief for approval
- **Session persistence:** Auto-checkpoint on session end (`.claude/session/latest.json`), file-log tracking on every edit, crash recovery with resume offer on next session start
- **Gate-aware deploy pipeline:** `run-pipeline.sh` accepts `mvp|team|production` argument and runs only the stages required for that gate level
- **Security scan script:** Standalone `security-scan.sh` wrapping gitleaks + secret pattern detection
- **Two-part error messages:** Every block message now shows what was blocked AND what Claude will do instead (`friendly_block_with_action()`)
- **Secret type detection:** Pre-write guard identifies specific secret types (AWS key, GitHub token, JWT, etc.) in block messages
- **6 new hook detections:** Unsafe CORS (`allow_origins=["*"]`), missing RLS on CREATE TABLE, unindexed foreign keys, console.log blocking in deploy mode (excluding test files), missing error handling in route handlers, `SELECT *` without `.limit()`
- **Configurable smoke test pages:** `SMOKE_PAGES` environment variable for custom page paths
- **Opus reviewer timeout:** 5-minute timeout with `OPUS_TIMEOUT` override; `--allowedTools` flag auto-detection
- **Packaging script:** `scripts/package.sh` builds distributable zip with correct `aulendil/` top-level directory
- **Manual updates:** 3 new slides (Start With Discovery, Deploy Flow, Tips for Working With Claude), offline fonts, version 1.4

### Changed
- **Token efficiency (~56% reduction):** Compressed CLAUDE.md, all 5 rules files, and global ~/.claude/CLAUDE.md — removed narration examples, tone headers, redundant code blocks, and duplicated rules
- **CLAUDE.md restructured:** Discovery Mode, Build Mode, Deploy Mode, Session Lifecycle sections; architectural rules deduplicated to rules files; sub-agent section replaced with pointer
- **Deploy pipeline refactored:** Mode switching via trap (auto-restores build mode on exit), tmp directory cleanup, stage-aware parallel execution
- **Stop hook streamlined:** All mid-process stderr removed; only final summary line printed; details go to audit.log only
- **Manual installation instructions:** Clarified that unzip creates `aulendil/` subdirectory; added explanation of automatic cleanup
- **Gitignore entries:** Streamlined comments in install.sh gitignore block

### Fixed
- **Zip structure:** Zip now extracts into `aulendil/` subdirectory (was extracting flat into project root, mismatching install.sh expectations)
- **deploy-state.json:** Nulled out contradictory populated fields (`deployed_at`, `deployed_by`, `deployed_version`) that conflicted with `deployment_status: "not-deployed"`
- **Opus reviewer:** Fixed `--allowedTools` flag check (now auto-detects if claude CLI supports it)

## [v1.0.0] — 2026-03-14
