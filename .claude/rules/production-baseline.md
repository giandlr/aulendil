# Production Baseline Features

These are the features that every real app needs but that managers rarely think to ask for.
Claude is responsible for surfacing them during Discovery and ensuring they are built.
Never assume they are out of scope.

> Full implementation specs, Tier levels, and gate enforcement for all features listed here
> are in `docs/enterprise-features.md`. This file defines *when* to ask and *what* to confirm.
> That file defines *how* to build it.

---

## Roles (slide 8 — set up automatically during bootstrap)

Every app starts with these 4 roles. Never rename or reduce them:

| Role | Default access |
|------|----------------|
| **Admin** | Full access to everything |
| **Manager** | Manage team members and resources |
| **Member** | View and edit own items |
| **Viewer** | Read-only access |

The first account created gets Admin automatically (first-user bootstrap). The dev user
(`dev@aulendil.local`) is seeded as Admin for local testing.

Claude adds app-specific permissions as features are built. The pipeline verifies roles
are correctly configured before deploy (Tier 1, production gate).

---

## Audience → Required Baseline

Use this table to determine what must be built and when to surface it.

| Feature | Just me | My team | Team + external |
|---------|---------|---------|-----------------|
| Forgot password / reset link | Offer | **Required** | **Required** |
| Email verification on signup | No | No | **Required** |
| Account settings page | No | **Required** | **Required** |
| User list (admin) | No | **Required** | **Required** |
| Role assignment UI (admin) | No | **Required** | **Required** |
| User deactivation (admin) | No | **Required** | **Required** |
| Invite-only onboarding | No | Offer | **Required** |
| Account lockout (N failed logins) | No | Offer | **Required** |
| Session management (timeout, force logout) | No | No | **Required** |
| Password complexity policies | No | Offer | **Required** |
| MFA (TOTP) | No | Offer | Offer (Required for finance/health apps) |
| Audit log | No | No | **Required** |

**Tier alignment:** All "Required" items for "Team + external" are Tier 1 (block pipeline if absent)
or Tier 2 (Opus advisory) per `docs/enterprise-features.md`. Claude does not wait for the Opus
reviewer to catch these — they are confirmed in Discovery and built proactively.

> **How audience and Tier interact:** The audience table above determines what Claude asks during Discovery. The Tier in `enterprise-features.md` determines pipeline enforcement. "Required" in this table = Claude recommends during Discovery and builds proactively. "Tier 1" in enterprise-features.md = pipeline blocks deployment if absent. These are complementary — Discovery catches it early, the pipeline catches it at deploy.

---

## When to Surface These

### During Discovery (Round 2) — mandatory
After collecting core features, present the applicable baseline as a checklist via AskUserQuestion.
Frame it as: *"Here are a few things users almost always expect — which should I include?"*

- For **"just me"** audience: skip the checklist, but mention forgot password as a quick add.
- For **"my team"** audience: checklist covers forgot password, account settings, user list,
  role assignment, user deactivation.
- For **"team + external"** audience: full checklist — all rows marked Required above.

**Never skip the baseline checklist for team or external apps**, even if the initial request
already includes 3+ features and would otherwise fast-path through Discovery.

> **"Offer" vs "Required":** "Required" means Claude must build it — no opt-out. "Offer" means Claude presents the option but accepts a "no" without pushing back.

**Checklist presentation:** Present baseline features in two groups for clarity:
- **"The basics"** (always recommended for team/external): Forgot password, account settings, user list, role assignment, user deactivation
- **"For tighter security"** (recommended for external users): Email verification, invite flow, account lockout, session management, password policies, audit log

This lets managers quickly say "yes to basics" without reading 12 individual items.

### During Build (new feature request)
If a manager asks for "user management", "settings", "permissions", or "admin panel" without
specifying scope, ask one clarification question before building:
*"Should admins be able to deactivate accounts, or just change roles?"* — then build both
unless there's a strong objection.

### Persistent Tracking (replaces one-time reminders)
After Discovery confirms the audience and baseline features, write the approved checklist
to `.claude/BASELINE.md`. During Build, check items off as they are implemented.

Before every new feature, check `.claude/BASELINE.md`. If unchecked items remain, mention
them once per session: *"We still have N baseline features to add. Want me to build one
before [requested feature]?"*

This replaces the one-time "after first substantive feature" reminder with persistent tracking
that survives across sessions.

---

## What to Build

Implementation recipes for each baseline feature: read `.claude/refs/baseline-recipes.md` when building.
Quick reference: each feature maps to `docs/enterprise-features.md` for full Tier/gate specs.

---

## Language Rules

- Never say "I didn't build that" — say "I can add [feature] now, it only takes a moment."
- Never present baseline features as optional nice-to-haves — frame them as "the basics that make the app feel complete and safe."
- When asking in Discovery, group related features in one checklist question — not one question per feature.
- Reference the 4 role names (Admin, Manager, Member, Viewer) consistently — never invent different names.
