# Enterprise Feature Requirements

This is the canonical reference for all enterprise features required in every application
built through Aulendil. Claude reads this file when a manager asks
"what features does my app need?"

Every feature has a Tier. **Tier 1** features block the pipeline if absent.
**Tier 2** features are flagged by the Opus reviewer as PRE-PRODUCTION REQUIRED advisories.

> **Gate Levels:** Each feature maps to a deploy gate level. MVP features are checked even for personal testing. Team features are required when sharing with colleagues. Production features are required for external or company-wide deployment.

---

## Identity & Access

| Feature | Description | Tier | Gate | Enforcement | Implementation (FastAPI / Supabase / Vue) |
|---------|-------------|------|------|-------------|-------------------------------------------|
| Email/password auth | Secure login with hashed passwords and session tokens | 1 | team | run-pipeline.sh stage, Opus review | Supabase Auth `signInWithPassword`; FastAPI verifies via `supabase.auth.getUser()` |
| Google Workspace SSO | OAuth 2.0 login restricted to organization domain | 1 | production | run-pipeline.sh stage, Opus review | Supabase Auth `signInWithOAuth({ provider: 'google' })`; restrict domain in Supabase Auth settings |
| MFA (TOTP + SMS) | Multi-factor authentication with TOTP primary and SMS fallback | 1 | production | run-pipeline.sh stage, Opus review | Supabase Auth MFA APIs: `mfa.enroll()`, `mfa.challenge()`, `mfa.verify()` |
| RBAC (4 roles minimum) | Role-based access: Admin, Manager, Member, Viewer | 1 | production | run-pipeline.sh stage, Opus review | `roles` + `user_roles` tables; custom JWT claims via Supabase hook; FastAPI `Depends(require_role("admin"))` |
| ABAC (data ownership) | Users only see their own data unless elevated role | 1 | team | Opus review | Supabase RLS policies: `auth.uid() = user_id` on all user-facing tables |
| Account lockout | Lock account after N failed login attempts | 1 | production | run-pipeline.sh stage, Opus review | `login_attempts` counter in profiles table; Supabase Auth hook or FastAPI middleware to check before auth |
| Invite-only onboarding | No open self-registration; admin sends invite with signed token | 1 | production | run-pipeline.sh stage, Opus review | `invitations` table (email, role_id, token, expires_at); registration validates invite token |
| Session management | Configurable timeout, force logout, concurrent session limits | 2 | production | Opus advisory | Supabase Auth session config; `active_sessions` table; cron to expire stale sessions |
| Password policies | Complexity rules, expiry, no password reuse | 2 | production | Opus advisory | Supabase Auth password strength config; `password_history` table checked on change |

---

## Resilience

| Feature | Description | Tier | Gate | Enforcement | Implementation |
|---------|-------------|------|------|-------------|----------------|
| Health endpoint | `GET /health` returns service + DB + dependency status | 1 | team | run-pipeline.sh stage, Opus review | FastAPI route: ping Supabase, check DB, return `{"status": "healthy", "db": "ok", "auth": "ok"}` |
| Graceful error pages | Custom 400, 401, 403, 404, 500 pages — no stack traces | 1 | team | post-edit-enforce, Opus review | FastAPI exception handlers; Nuxt `error.vue` layout with friendly messages |
| Rate limiting | Rate limits on all API endpoints, stricter on auth | 1 | production | post-edit-enforce, run-pipeline.sh stage, Opus review | `slowapi` library with `Limiter` on FastAPI app; per-route decorators `@limiter.limit("10/minute")` |
| Idempotency on writes | All write operations are idempotent (safe to retry) | 1 | production | Opus review | `Idempotency-Key` header; `idempotency_keys` table storing (key, response, expires_at) |
| Maintenance mode | Read-only or offline mode without redeploy | 2 | production | Opus advisory | `feature_flags` table with `maintenance_mode` key; middleware checks flag, returns 503 if active |
| Feature flags | Per-role, per-user, and global feature toggles | 2 | production | Opus advisory | `feature_flags` table; FastAPI `Depends(require_flag("feature_name"))`; Vue `useFeatureFlag()` composable |

---

## Data & UX

| Feature | Description | Tier | Gate | Enforcement | Implementation |
|---------|-------------|------|------|-------------|----------------|
| Pagination (all lists) | Every list endpoint and UI table uses pagination — never unbounded | 1 | production | post-edit-enforce, run-pipeline.sh stage, Opus review | Cursor-based pagination; FastAPI `limit`/`cursor` params; Vue `usePagination()` composable |
| Loading states | Every async operation shows a loading indicator | 1 | team | post-edit-enforce, Opus review | Vue: `const loading = ref(true)` pattern; skeleton components in `frontend/components/` |
| Error states | Every async operation handles and displays errors | 1 | team | post-edit-enforce, Opus review | Vue: `const error = ref(null)` pattern; `<ErrorAlert>` component with retry action |
| Empty states | Every list/table shows meaningful empty state | 1 | team | post-edit-enforce, Opus review | Vue: `v-if="items.length === 0"` with `<EmptyState>` component |
| Input sanitization | Sanitize before storage and before rendering | 1 | production | Opus review | Backend: Pydantic validators with `bleach` or manual strip; Frontend: Vue auto-escapes by default, avoid `v-html` |
| Confirmation dialogs | All destructive actions require user confirmation | 1 | production | Opus review | `<ConfirmDialog>` component; `useConfirm()` composable wrapping destructive service calls |
| Form validation | Inline, real-time, pre-submission validation | 1 | team | Opus review | `vee-validate` + `zod` schemas; `<FormField>` wrapper showing inline errors |
| Optimistic UI | Immediate feedback before server confirmation | 2 | production | Opus advisory | Pinia actions update state immediately, revert on server error |
| Search with debounce | Server-side search, not client filtering, with debounce | 2 | production | Opus advisory | `useDebouncedSearch()` composable (300ms); FastAPI search endpoint with `ilike` query |
| Auto-save drafts | Forms auto-save work in progress | 2 | production | Opus advisory | `useDraft()` composable saving to localStorage; restore on page load |
| Bulk operations | Select multiple items in lists for batch actions | 2 | production | Opus advisory | `useSelection()` composable; batch API endpoints accepting arrays of IDs |
| Optimistic locking | Conflict detection on concurrent edits | 2 | production | Opus advisory | `version` column on editable tables; `If-Match` header with ETag; 409 on mismatch |
| Undo / soft delete grace | Soft delete with timed undo option | 2 | production | Opus advisory | `deleted_at` timestamp + 30s grace period toast with undo button |

---

## Security

| Feature | Description | Tier | Gate | Enforcement | Implementation |
|---------|-------------|------|------|-------------|----------------|
| HTTPS only | HTTP redirect + HSTS header | 1 | production | Opus review | Vercel handles HTTPS redirect; add `Strict-Transport-Security` header in Nuxt config |
| CSP headers | Content Security Policy preventing XSS | 1 | production | run-pipeline.sh stage, Opus review | Nuxt `security` module or custom middleware setting `Content-Security-Policy` header |
| CORS allowlist | Explicit origin allowlist, no wildcard | 1 | production | run-pipeline.sh stage, Opus review | FastAPI `CORSMiddleware` with `allow_origins=["https://yourdomain.com"]` |
| No secrets in frontend | Service role key and secrets never in client code | 1 | mvp | pre-write-guard, post-edit-enforce, Opus review | Enforced by hooks; only `SUPABASE_ANON_KEY` in frontend |
| Dependency scanning | Automated vulnerability scanning of packages | 2 | production | stop-final-audit, Opus advisory | `npm audit` + `pip-audit` in stop hook; confirm in pipeline results |

---

## Accessibility & Mobile

| Feature | Description | Tier | Gate | Enforcement | Implementation |
|---------|-------------|------|------|-------------|----------------|
| Mobile responsiveness | 320px to 4K, iOS Safari + Android Chrome | 1 | team | Opus review | TailwindCSS responsive prefixes (`sm:`, `md:`, `lg:`, `xl:`); test with Playwright viewports |
| Keyboard navigation | All interactive elements reachable via keyboard | 1 | production | post-edit-enforce (a11y), Opus review | `tabindex`, `@keydown` handlers, focus management; Playwright a11y tests |
| WCAG 2.1 AA contrast | Color contrast compliance for all text | 1 | production | Opus review | TailwindCSS color palette meeting 4.5:1 ratio; Lighthouse accessibility audit ≥ 90 |
| PWA support | Installable, offline read support | 2 | production | Opus advisory | `@vite-pwa/nuxt` module; service worker caching read-only data |
| Screen reader support | ARIA labels, semantic HTML, logical focus order | 2 | production | Opus advisory | `<nav>`, `<main>`, `<section>` landmarks; `aria-label` on all interactive elements |
| Reduced motion | Respect `prefers-reduced-motion` | 2 | production | Opus advisory | TailwindCSS `motion-reduce:` variant; disable animations when preference is set |

---

## Observability

| Feature | Description | Tier | Gate | Enforcement | Implementation |
|---------|-------------|------|------|-------------|----------------|
| Structured JSON logging | timestamp, level, correlation ID, user ID, action | 1 | production | Opus review | Python `structlog` library; middleware injects correlation ID; JSON formatter for stdout |
| Health check | Service + DB + dependency status endpoint | 1 | team | run-pipeline.sh stage | (Same as Resilience section — `/health` endpoint) |
| Error tracking | Sentry or equivalent integration | 2 | production | Opus advisory | `sentry-sdk` for Python FastAPI; `@sentry/vue` for frontend; DSN in env vars |
| Performance monitoring | p50/p95/p99 per endpoint | 2 | production | Opus advisory | FastAPI middleware recording request duration; Sentry performance or custom metrics |
| Admin activity dashboard | User activity overview for administrators | 2 | production | Opus advisory | `audit_log` table + admin-only page with filters and charts |
| In-app help | Contextual tooltips + help panel | 2 | production | Opus advisory | `<HelpTooltip>` component; `/help` page; contextual `?` icons linking to docs |
| Feedback widget | User feedback collection | 2 | production | Opus advisory | `feedback` table; `<FeedbackWidget>` floating component; POST `/api/feedback` |

---

## Notifications

| Feature | Description | Tier | Gate | Enforcement | Implementation |
|---------|-------------|------|------|-------------|----------------|
| In-app notifications | Real-time, unread count, mark as read, history | 2 | production | Opus advisory | `notifications` table; Supabase Realtime subscription; `useNotifications()` composable |
| Email notifications | Emails for key events (invite, password reset, alerts) | 2 | production | Opus advisory | Resend SDK (`resend.com`); FastAPI background tasks; email templates |
| Browser push | Web Push API for time-sensitive alerts | 2 | production | Opus advisory | VAPID keys; `push_subscriptions` table; service worker push handler |
| Notification preferences | Per-user channel and event type control | 2 | production | Opus advisory | `notification_preferences` table (user_id, channel, event_type, enabled) |
| Digest mode | Optional daily/weekly digest instead of real-time | 2 | production | Opus advisory | Cron job aggregating notifications; user preference for digest frequency |

---

## Compliance

| Feature | Description | Tier | Gate | Enforcement | Implementation |
|---------|-------------|------|------|-------------|----------------|
| Audit log | Immutable: who, what, which record, when, from which IP | 2 | production | Opus advisory | `audit_log` table with DB triggers; middleware logging user actions; immutable (no UPDATE/DELETE RLS) |
| Data export | User self-export + admin full export | 2 | production | Opus advisory | Background job generating CSV/JSON; signed Supabase Storage URL for download |
| Data retention | Configurable retention policies | 2 | production | Opus advisory | `retention_policies` config; cron job purging data past retention period |
| Consent tracking | ToS/privacy policy version + acceptance timestamp | 2 | production | Opus advisory | `terms_acceptances` table (user_id, version, accepted_at, ip_address) |
| Right to erasure | GDPR-compliant data deletion workflow | 2 | production | Opus advisory | Stored procedure anonymizing PII; `erasure_requests` table tracking status |
