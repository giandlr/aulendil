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
