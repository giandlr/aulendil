# Production Baseline Features

These are the features that every real app needs but that managers rarely think to ask for.
Claude is responsible for surfacing them and building them — never assume they're out of scope.

## Audience → Required Baseline

| Audience | Required features |
|----------|-------------------|
| Just me | None mandatory — but offer forgot password |
| My team | Forgot password, basic user list (admin), role assignment |
| Team + external people | All of the above + email verification, invite flow or self-register choice, account settings, user deactivation |

## The Baseline Feature Set

### Authentication
- **Forgot password / reset link** — Always include unless audience is "just me" and they explicitly decline. Supabase Auth `resetPasswordForEmail()` + a `/reset-password` page.
- **Email verification** — Required for apps with external users. Supabase Auth `email_confirm` setting.
- **Account settings page** — Change display name, change password, sign out all devices. Required at Team+.

### User Management (admin)
- **User list** — Admin can see all users: name, email, role, status (active/inactive), last login. Required at Team+.
- **Role assignment** — Admin can change any user's role from the user list. Required at Team+.
- **Deactivate / reactivate user** — Soft disable (set `active = false`), not delete. Required at Team+.
- **Invite user** (external apps) — Admin sends invite email; user sets their own password. Required when audience includes external people.

### Access
- **First-user bootstrap** — The first account created automatically gets the Admin role. Prevents lockout.
- **Admin-only guard** — At least one page/section is admin-restricted so RBAC is visibly working from day one.

## When to Build These

**During Discovery (Round 2):** After collecting core features, present the applicable baseline list as a quick yes/no checklist via AskUserQuestion. Frame it as: "Here are a few things users almost always need — which should I include?"

**During Build (new feature request):** If a manager asks for "user management" or "settings" without specifying scope, ask one clarifying question before building: "Should admins be able to deactivate users, or just change their roles?" Then build both if there's no strong objection.

**Opportunistic:** If the app grows to the point where these are obviously missing (e.g. no way for a user to reset their password), flag it in plain English: "I noticed there's no password reset yet — want me to add that now? It takes a few minutes."

## What to Build for Each Feature

### Forgot Password
- Backend: `POST /auth/forgot-password` → calls `supabase.auth.resetPasswordForEmail()`
- Frontend: `/forgot-password` page (email input) + `/reset-password` page (new password input, reads token from URL hash)
- No custom email needed — Supabase sends the reset email automatically

### User Management Page
- Frontend: `/app/admin/users` — table of all users with columns: Name, Email, Role (dropdown), Status (active toggle), Last login
- Backend: `GET /admin/users` (admin only), `PATCH /admin/users/:id` (role + active)
- RLS: only service role reads `auth.users`; user records in `public.users` table

### Role Assignment
- Dropdown in user table row — saves to `user_roles` on change
- Instant feedback (optimistic update), error toast on failure

### User Deactivation
- Toggle in user table — sets `active = false` in `public.users`
- Middleware checks `active` on every request — returns 403 if inactive
- Does not delete the account or any data

### Invite Flow
- Frontend: `/app/admin/users` → "Invite user" button → email + role picker modal
- Backend: `POST /admin/invite` → `supabase.auth.admin.inviteUserByEmail()` with role metadata
- Invited user lands on `/accept-invite` page to set their password

### Account Settings
- Frontend: `/app/settings` — tabs: Profile (name, avatar), Security (change password, active sessions), Notifications (if applicable)
- Backend: `PATCH /users/me` for profile; Supabase Auth `updateUser()` for password change

## Language Rules

- Never say "I didn't build that" — say "I can add password reset now, it only takes a moment"
- Never present these as optional nice-to-haves — frame them as "the basics that make the app feel complete"
- When asking about baseline features in Discovery, group them as a checklist, not individual questions
