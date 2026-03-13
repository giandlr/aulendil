# Managers' Agent Fleet

**Build enterprise apps by describing what you want in plain English.** Quality, security, and testing happen automatically behind the scenes.

This toolkit turns [Claude Code](https://docs.anthropic.com/en/docs/claude-code) into a full engineering team for non-technical managers. You describe features in natural language, Claude builds production-quality code, and an automated pipeline ensures everything works before you share it.

---

## Quick Start

```bash
# 1. Create a new project and initialize git
mkdir my-app && cd my-app && git init

# 2. Copy and unzip the toolkit
cp /path/to/managers-agent-fleet.zip .
unzip managers-agent-fleet.zip

# 3. Install the toolkit into your project
bash managers-agent-fleet/install.sh

# 4. Bootstrap your app (scaffolds everything + starts the servers)
bash scripts/sprout-bootstrap.sh

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

A development user (`dev@sprout.local` / `devpassword123`) is seeded automatically for local testing.

---

## How It Works

### Two Modes

| Mode | When | What Happens |
|------|------|--------------|
| **Build** (default) | You're creating features | Build freely. Only security issues are blocked. Claude auto-fixes quality and explains what it did in plain English. |
| **Deploy** | You say "ship it" | Claude asks who it's for and runs the appropriate level of checks before sharing. |

### Three Deploy Levels

| Level | Who It's For | What's Checked |
|-------|-------------|----------------|
| **MVP** | Just you testing | Security scan, app starts, happy path works |
| **Team** | Sharing with colleagues | + Unit tests pass, auth works, errors handled |
| **Production** | External users | + Full test suite, performance, independent Opus code review |

Start at MVP and graduate to Production as your project matures.

---

## What's Inside

```
your-project/
├── .claude/
│   ├── agents/                 # Specialist AI workers (tests, pipeline, review)
│   ├── hooks/                  # Real-time guards (security, quality)
│   │   └── lib/                # Shared hook utilities
│   ├── rules/                  # Domain-specific standards (API, auth, DB, frontend)
│   ├── reviewers/              # Opus code reviewer system prompt
│   ├── scripts/                # Pipeline scripts (smoke test, review, release)
│   ├── settings.json           # Claude Code permissions
│   ├── mode                    # Current mode: "build" or "deploy"
│   └── deploy-gates.json       # Gate level definitions (MVP/Team/Production)
├── docs/
│   ├── architecture.md         # System architecture reference
│   ├── api-conventions.md      # API design standards
│   ├── tech-stack.md           # Technology decisions (single source of truth)
│   ├── done-checklist.md       # Definition of done per gate level
│   ├── enterprise-features.md  # Enterprise feature requirements
│   └── changelog-guide.md      # Changelog conventions
├── scripts/
│   └── sprout-bootstrap.sh     # One-command project setup
├── manual/
│   └── sprout-guide.html       # Visual guide (open in browser)
├── CLAUDE.md                   # Project rules for Claude Code
├── CHANGELOG.md                # Auto-maintained release history
└── install.sh                  # Toolkit installer
```

---

## Tech Stack

The toolkit scaffolds projects with:

- **Frontend:** Nuxt 3 / Vue 3 (Composition API) + TypeScript + TailwindCSS
- **State:** Pinia
- **Forms:** vee-validate + zod
- **Backend:** FastAPI (Python 3.9+, async)
- **Database:** Supabase (PostgreSQL with Row Level Security)
- **Auth:** Supabase Auth (JWT)
- **Testing:** Vitest + Playwright (frontend), pytest (backend)
- **Quality:** ESLint, Prettier, vue-tsc, ruff, mypy, bandit

All technology decisions are defined in `docs/tech-stack.md`.

---

## The Bootstrap Script

`scripts/sprout-bootstrap.sh` takes you from an empty project to a running app in one command:

| Phase | What It Does |
|-------|-------------|
| **1. Scaffold** | Creates Nuxt 3 frontend, FastAPI backend, and Supabase directory structure |
| **2. Configure** | Installs all dependencies, creates config files, sets up dev plugins |
| **3. Supabase** | Initializes and starts local Supabase, extracts credentials, seeds a dev user |
| **4. Start** | Launches backend and frontend dev servers |
| **5. Dev Tools** | Installs gitleaks, k6, and sets file permissions |

### Prerequisites

- **Node.js** (18+)
- **Python** (3.9+)
- **Docker** (for local Supabase)

Docker is optional during build mode — the app works as a UI shell without a database, showing empty states and an informational banner. Supabase is required at the Team and Production deploy levels.

---

## Protection Layers

### Layer 1 — Rules
Claude automatically follows project standards for API design, authentication, database patterns, and frontend conventions. Defined in `.claude/rules/`.

### Layer 2 — Guards (Hooks)
Real-time checks on every code write and command execution:
- **Always blocked:** Hardcoded secrets, dangerous commands, admin keys in frontend
- **Deploy mode only:** Lint errors, type errors, missing tests

### Layer 3 — Specialist Agents
Parallel AI workers for tests, security scans, and performance checks. The pipeline orchestrator coordinates them without touching code itself.

### Layer 4 — Pipeline
Gate-level validation when you deploy. Runs only the checks appropriate for your chosen level.

### Layer 5 — Opus Review (Production only)
An independent AI reviewer (Claude Opus) examines the code with zero knowledge of the development session. Like an external auditor.

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

---

## The Manual

Open `manual/sprout-guide.html` in any browser for a visual walkthrough of the entire system. Navigate with arrow keys or click the dots.

---

## Philosophy

> "The best engineering practices shouldn't require an engineering degree."

- **Build freely** — Your creative flow is sacred. Quality enforcement stays out of your way during development.
- **Deploy safely** — When you're ready to share, the right level of checks activates automatically.
- **Plain English always** — Claude never mentions tool names or technical jargon. It explains what it did and why in language anyone can understand.
- **Progressive gates** — Start simple with MVP, graduate to Production when ready. The system grows with you.
