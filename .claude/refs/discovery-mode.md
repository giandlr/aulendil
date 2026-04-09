## Discovery Mode

**Trigger:** User says "build me...", "I want...", "create...", "make me..." AND project is greenfield (`[APP_NAME]` placeholder still present in CLAUDE.md or no migrations exist).

**Round 1 — Big Picture (2 questions via AskUserQuestion with clickable options):**
- "What kind of app is this closest to?" (dashboard / form tool / communication tool / scheduling tool / other)
- "Who will use this?" (just me / my team / team + external people)

**Round 2 — Core Features + Baseline (3–4 questions):**
- Present feature options as multi-select based on Round 1. For "other" app type, use a generic feature list: CRUD operations / search & filtering / file upload / notifications / reports & export / approval workflows / calendar & scheduling.
- Challenge: "Is there anything I'm missing? Any approval workflows or external system connections?"
- "Frontend preference?" (Vue + Nuxt 3 (default) / React + Next.js) — writes `FRONTEND_FRAMEWORK=nuxt` or `FRONTEND_FRAMEWORK=next` to `.env`
- "Do you need a mobile app?" (yes — mobile + web / web only)
- **Production baseline checklist** (see `production-baseline.md`): Based on the audience answer from Round 1, present the applicable baseline features as a yes/no checklist via AskUserQuestion. Frame as: "Here are a few things users almost always expect — which should I include?" For team/external apps this must include: forgot password, user management page, role assignment, user deactivation. For external apps also include: email verification, invite flow.

*Frontend answer writes `FRONTEND_FRAMEWORK=nuxt` or `next` to `.env`. Mobile answer writes `INCLUDE_MOBILE=true` to `.env`. Bootstrap reads both on next run.*

**Round 3 — Data & Access (1 question):**
- "Should everyone see everything, or only their own stuff?" (everyone / own only / role-based)

**Skip condition:** If initial request has 3+ features AND mentions audience, still run the baseline checklist — never skip it for team/external apps.

**Mobile follow-up (if mobile = yes):** Ask one additional question: "Any mobile-specific needs?" with options: offline support / push notifications / camera or GPS / none of these. Record answers in brief.md under a "Mobile requirements" section.

**Design direction (Round 2 addition):** After features, ask: "Any brand colours, logo, or aesthetic preferences?" If user says no or is vague, offer 3 quick options: "Modern editorial (clean serif fonts, bold contrasts)" / "Warm minimal (rounded shapes, soft tones)" / "Bold industrial (sharp edges, dark palette)". Record the choice in `.claude/brief.md` under "Design direction" so all future components follow it consistently.

**Output:** Write the following files:
1. `.claude/brief.md` — app name, description, users, features (including confirmed baseline features), data model sketch, access rules, design direction, mobile requirements (if applicable), out-of-scope
2. `.claude/BASELINE.md` — approved baseline features as a markdown checklist (`- [ ] Feature name`), with audience level noted at the top. Build mode checks this file before every feature and marks items `[x]` as they are completed.

Then: update `[APP_NAME]` in CLAUDE.md, write `build` to `.claude/mode`, narrate plan, ask "Does this look right?"

**Scope change:** If the user later expands the audience (e.g., "actually my team will use this" or "we need to add external users"), re-present the baseline checklist for the new audience level and update `.claude/BASELINE.md` with any newly required features. This can happen at any point during Build mode — not just during Discovery.
