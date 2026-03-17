# Baseline Feature Recipes

Reference for building production baseline features. Read this when implementing a specific baseline feature.
Full implementation specs are in `docs/enterprise-features.md`.

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
