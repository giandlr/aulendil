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

---

## When to Surface These

### During Discovery (Round 2) — mandatory
After collecting core features, present the applicable baseline as a checklist via AskUserQuestion.
Frame it as: *"Here are a few things users almost always expect — which should I include?"*

- For **"just me"** audience: skip the checklist, but mention forgot password as a quick add.
- For **"my team"** audience: checklist covers forgot password, account settings, user list,
  role assignment, user deactivation, account lockout.
- For **"team + external"** audience: full checklist — all rows marked Required above.

**Never skip the baseline checklist for team or external apps**, even if the initial request
already includes 3+ features and would otherwise fast-path through Discovery.

### During Build (new feature request)
If a manager asks for "user management", "settings", "permissions", or "admin panel" without
specifying scope, ask one clarification question before building:
*"Should admins be able to deactivate accounts, or just change roles?"* — then build both
unless there's a strong objection.

### Opportunistic (any time during Build Mode)
After the first substantive feature in a new project, check whether baseline features have been
confirmed and built. If any Required items are missing for the confirmed audience, flag in
plain English and offer to add them before continuing:
*"I noticed there's no way for users to reset their password yet — want me to add that now?
It only takes a few minutes."*

---

## What to Build (summary — see enterprise-features.md for full spec)

### Forgot Password
Supabase Auth `resetPasswordForEmail()` + `/forgot-password` page (email input) +
`/reset-password` page (reads token from URL hash, sets new password).
No custom email template needed — Supabase sends automatically.
*See enterprise-features.md → Identity & Access → "Password policies"*

### Email Verification
Enable `email_confirm` in Supabase Auth project settings.
Add a `/verify-email` holding page shown after registration.
*See enterprise-features.md → Identity & Access → "Email/password auth"*

### Account Settings Page
`/app/settings` — Profile tab (display name, avatar), Security tab (change password,
sign out all devices). Uses Supabase Auth `updateUser()` for password changes.
*See enterprise-features.md → Identity & Access → "Session management"*

### User List (admin)
`/app/admin/users` — table: Name, Email, Role (dropdown), Status (active toggle), Last login.
Backend: `GET /admin/users` + `PATCH /admin/users/:id`. Admin-only route guard.
*See enterprise-features.md → Identity & Access → "RBAC (4 roles minimum)"*

### Role Assignment
Role dropdown in the user table row saves to `user_roles` on change.
Uses the 4 named roles: Admin, Manager, Member, Viewer — no custom role names without
explicit manager request.
*See enterprise-features.md → Identity & Access → "RBAC (4 roles minimum)"*

### User Deactivation
Toggle in user table sets `active = false` in `public.users` (soft disable, never delete).
Middleware checks `active` on every authenticated request — 403 if inactive.
*See enterprise-features.md → Identity & Access → "Invite-only onboarding"*

### Invite Flow
Admin sends invite from user list → `supabase.auth.admin.inviteUserByEmail()` with role metadata.
Invited user lands on `/accept-invite` to set password.
*See enterprise-features.md → Identity & Access → "Invite-only onboarding"*

### Account Lockout
`login_attempts` counter in `profiles` table. After 5 failures: lock for 15 minutes.
FastAPI middleware checks before processing auth. Reset counter on successful login.
*See enterprise-features.md → Identity & Access → "Account lockout"*

### Session Management
Configurable session timeout in Supabase Auth settings. Admin can force-logout a user via
Supabase Admin API `supabase.auth.admin.signOut(userId)`. Display active sessions on
account settings Security tab.
*See enterprise-features.md → Identity & Access → "Session management"*

### Password Policies
Minimum 8 characters enforced in Supabase Auth settings. Frontend zod schema matches
the same rules. Add to account settings change-password form.
*See enterprise-features.md → Identity & Access → "Password policies"*

### Audit Log
`audit_log` table: `(id, user_id, action, table_name, record_id, old_values, new_values, ip, created_at)`.
DB triggers on sensitive tables. Admin-only `/app/admin/audit` page with filters.
*See enterprise-features.md → Compliance → "Audit log"*

---

## Language Rules

- Never say "I didn't build that" — say "I can add [feature] now, it only takes a moment."
- Never present baseline features as optional nice-to-haves — frame them as "the basics that make the app feel complete and safe."
- When asking in Discovery, group related features in one checklist question — not one question per feature.
- Reference the 4 role names (Admin, Manager, Member, Viewer) consistently — never invent different names.
