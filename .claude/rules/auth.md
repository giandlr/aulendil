---
globs: ["backend/middleware/**", "backend/auth/**", "backend/routes/auth*", "frontend/composables/useAuth*", "frontend/middleware/**"]
---

## Supabase Auth

- Use `supabase.auth.getUser()` server-side to verify sessions
- Derive user identity from verified JWT — never trust client-supplied user IDs
- Service role key in backend only — auto-switch to anon key in frontend
- Use `onAuthStateChange` on frontend to react to session changes

## JWT Verification

- Verify both signature and expiry; reject missing/unexpected claims
- Use Supabase's `getUser()` on backend (handles verification); only manually decode JWTs if needed
- JWT secret from environment variables only

## Session Management

- Store refresh tokens hashed; invalidate on logout via `supabase.auth.signOut()`
- Token expiry: access 1hr, refresh 7 days; single-use refresh tokens

## Password Security

- bcrypt min 12 rounds (Supabase Auth default); min 8 char password length
- Never log passwords, tokens, or secrets

## Error Messages

- Uniform auth errors: "Invalid email or password" (never "user not found"), "If this email exists, a reset link has been sent" (never "email not found")
- Rate limit login attempts per IP and per email

## RBAC

- Check permissions server-side on every request — never rely on frontend hiding UI
- Use RLS policies as primary access control; roles in `user_roles` table
- Verify role claims in middleware; require explicit admin role for admin endpoints

## Frontend Auth Middleware

- Check auth in Nuxt route middleware; redirect unauthenticated to login
- Store auth state in Pinia via composable; unsubscribe Realtime channels in `onUnmounted`

## External Access

When external users (suppliers, customers, partners) are mentioned:
- Separate RLS policies scoped to org/tenant; dedicated role with minimal permissions
- Stricter rate limiting (5/min vs 10/min); invite-only registration

### Dual-Portal Pattern

Internal (`/app/`): full access, SSO. External (`/portal/`): limited views, invite-only email/password, scoped RLS.

## CSRF Protection

CSRF is not applicable — authentication uses Bearer tokens in the Authorization header, not cookies. No CSRF tokens needed. Document this explicitly so future developers don't add unnecessary CSRF middleware.
