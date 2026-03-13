---
globs: ["backend/middleware/**", "backend/auth/**", "backend/routes/auth*", "frontend/composables/useAuth*", "frontend/middleware/**"]
---

> **Tone:** Apply these patterns automatically. Narrate what you did in plain English — never mention tool names or jargon.

## Supabase Auth Patterns

- Always use `supabase.auth.getUser()` server-side to verify sessions. Narrate: "I set up session verification so the app confirms who's logged in on every request."
- Always derive user identity from the verified JWT — never trust client-supplied user IDs.
- Always keep the service role key in backend code only. If you catch yourself about to use it in frontend, switch to the anon key automatically. Narrate: "I used the safe public key for frontend code."
- The `SUPABASE_ANON_KEY` is safe for frontend — it respects security policies.
- Always use the Supabase client's `onAuthStateChange` on the frontend to react to session changes.

## JWT Verification

- Always verify both JWT signature and expiry. Narrate: "I set up token verification to keep user sessions secure."
- Always reject tokens with missing or unexpected claims.
- On the backend, use Supabase's `getUser()` which handles verification — only manually decode JWTs if there's a specific reason.
- If manually verifying, always pull the JWT secret from environment variables. Narrate: "I'm reading the secret from the environment so it's never hardcoded."

## Session Management

- Always store refresh tokens hashed in the database. Narrate: "I'm storing tokens securely so they can't be stolen from the database."
- On logout, always invalidate the session server-side by calling `supabase.auth.signOut()`.
- Set reasonable token expiry times (access: 1 hour, refresh: 7 days).
- Always implement token rotation — each refresh token is single-use.

## Password Security

- Always use bcrypt with a minimum of 12 rounds for password hashing (Supabase Auth handles this by default).
- Always enforce minimum password length of 8 characters.
- Never log passwords, tokens, or secrets — even in debug mode.

## Error Messages

- Always use uniform authentication error messages to avoid revealing whether an email exists. Narrate: "I made login errors generic so attackers can't figure out which emails are registered."
- For login failures: "Invalid email or password" — never "user not found" or "wrong password."
- For password reset: "If this email exists, a reset link has been sent" — never "email not found."
- Always rate limit login attempts per IP and per email to prevent brute force.

## RBAC (Role-Based Access Control)

- Always check permissions server-side on every request — never rely on frontend hiding UI elements. Narrate: "I added server-side permission checks so access control can't be bypassed."
- Always use Supabase RLS policies as the primary access control mechanism.
- Define roles in a `user_roles` table with RLS policies that restrict role assignment.
- Always verify role claims in middleware before allowing access to protected routes.
- Always require explicit admin role verification for admin endpoints — not just "authenticated."

## Frontend Auth Middleware

- Always check auth state in Nuxt route middleware before rendering protected pages. Narrate: "I added a login check so unauthenticated users get redirected."
- Always redirect unauthenticated users to login — never show a flash of protected content.
- Always store auth state in a Pinia store via a composable — not in localStorage directly.
- Always unsubscribe from Supabase Realtime channels in `onUnmounted` to prevent memory leaks.

## External Access Patterns

When the manager mentions external users (suppliers, customers, partners):

- Create separate RLS policies scoped to organization/tenant.
- External users get a dedicated role with minimal permissions.
- External-facing routes get stricter rate limiting (5/minute vs 10/minute for internal).
- Use invite-only registration for external users (no self-signup).
- Narrate: "I set up a separate access level for external users so they can only see what's relevant to them."

### Dual-Portal Pattern
When both internal and external users need access:
- **Internal portal:** Full access, company SSO auth, all features.
- **External portal:** Limited views, separate auth flow (invite-only email/password), scoped RLS policies.
- Scaffold separate route groups: `/app/` for internal, `/portal/` for external.
- Narrate: "I created a separate portal for external users with its own login and restricted views."
