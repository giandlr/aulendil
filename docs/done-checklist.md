# Definition of Done

Choose the checklist that matches your deploy gate level.

---

## MVP Gate — "Just me testing"

Quick validation that the app works and is secure.

- [ ] App starts without errors
- [ ] Core feature works end-to-end (happy path)
- [ ] No hardcoded secrets in code (gitleaks passes)
- [ ] No service role key in frontend code
- [ ] No direct Supabase calls outside services/
- [ ] Basic navigation works
- [ ] Data saves and loads correctly

---

## Team Gate — "Sharing with colleagues"

Everything in MVP, plus:

### Tests
- [ ] Unit tests pass (backend + frontend)
- [ ] Line coverage ≥ 60%
- [ ] Branch coverage ≥ 50%
- [ ] Every new file has a test file

### Security
- [ ] Authentication works (login/logout)
- [ ] Users can only see their own data (RLS working)
- [ ] No secrets in any tracked file

### Error Handling
- [ ] Pages show loading indicators during data fetch
- [ ] Error messages appear when something goes wrong
- [ ] Empty lists show a helpful message

### Basics
- [ ] Forms validate input before submission
- [ ] Works on mobile screens
- [ ] No TODO/FIXME markers left in changed files

---

## Production Gate — "External users / company-wide"

Everything in Team, plus:

### Full Test Suite
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] All e2e tests pass
- [ ] Line coverage ≥ 80%, branch coverage ≥ 70%
- [ ] No skipped tests in new code

### Enterprise Features (Tier 1)

#### Identity & Access
- [ ] Email/password authentication with secure session management
- [ ] Google Workspace SSO (OAuth 2.0 with org domain restriction)
- [ ] MFA enabled (TOTP primary + SMS fallback)
- [ ] RBAC implemented with at minimum: Admin, Manager, Member, Viewer roles
- [ ] ABAC enforced (data ownership scoping via RLS — users see only their own data unless elevated)
- [ ] Account lockout after failed login attempts
- [ ] Invite-only onboarding (no open self-registration; admin sends invite)

#### Resilience
- [ ] `GET /health` endpoint returning service + DB + dependency status
- [ ] Graceful error pages for 400, 401, 403, 404, 500 (no stack traces exposed)
- [ ] Rate limiting on all API endpoints (stricter on auth endpoints)
- [ ] Idempotency on all write operations (Idempotency-Key header support)

#### Data & UX
- [ ] Pagination on ALL list endpoints and UI tables (never unbounded queries)
- [ ] Loading states for every async operation
- [ ] Error states for every async operation
- [ ] Empty states for every list/table
- [ ] Input sanitization before storage and before rendering
- [ ] Confirmation dialogs for all destructive actions (delete, revoke, etc.)
- [ ] Form validation (inline, real-time, pre-submission via vee-validate + zod)

#### Security
- [ ] HTTPS only (HTTP redirect + HSTS header)
- [ ] Content Security Policy (CSP) headers configured
- [ ] CORS with explicit origin allowlist (no wildcard `*`)
- [ ] Secrets never referenced in frontend code (enforced by hooks)

#### Accessibility & Mobile
- [ ] Mobile responsiveness (320px to 4K, iOS Safari + Android Chrome)
- [ ] Keyboard navigation on all interactive elements
- [ ] WCAG 2.1 AA color contrast compliance

#### Observability
- [ ] Structured JSON logging (timestamp, level, correlation ID, user ID, action)
- [ ] Health check endpoint (see Resilience above)

### Enterprise Features (Tier 2 — Pre-Production)

#### Identity & Access
- [ ] Session management (configurable timeout, force logout, concurrent session limits)
- [ ] Password policies (complexity rules, expiry, no password reuse)

#### Notifications
- [ ] In-app notifications (real-time via Supabase Realtime, unread count, mark as read, history)
- [ ] Email notifications for key events (invites, password resets, alerts)
- [ ] Browser push notifications for time-sensitive alerts
- [ ] Notification preferences (per-user channel and event type control)
- [ ] Digest mode option (daily/weekly digest alternative)

#### Compliance
- [ ] Audit log (immutable: who, what, which record, when, from which IP)
- [ ] Data export (user self-export + admin full export)
- [ ] Data retention policies (configurable, with automated enforcement)
- [ ] Consent tracking (ToS/privacy policy version + acceptance timestamp)
- [ ] Right to erasure workflow (GDPR-compliant PII anonymization)

#### Resilience
- [ ] Maintenance mode (read-only or offline without redeploy)
- [ ] Feature flags (per-role, per-user, global toggles)

#### Performance
- [ ] Caching strategy with defined TTLs and mutation invalidation
- [ ] Lazy loading for images and heavy components
- [ ] Optimistic UI (immediate feedback before server confirmation)
- [ ] Search with debounce (server-side, not client-side filtering)

#### Mobile & Accessibility
- [ ] PWA support (installable, offline read support)
- [ ] Screen reader support (ARIA labels, semantic HTML, logical focus order)
- [ ] Reduced motion support (`prefers-reduced-motion` respected)

#### Data Integrity
- [ ] Optimistic locking (conflict detection on concurrent edits)
- [ ] Auto-save drafts on forms
- [ ] Undo / soft delete with grace period
- [ ] Bulk operations on list views

#### Observability
- [ ] Error tracking integration (Sentry or equivalent)
- [ ] Performance monitoring (p50/p95/p99 per endpoint)
- [ ] User activity dashboard for admins
- [ ] In-app help (contextual tooltips + help panel)
- [ ] Feedback widget

#### Security
- [ ] Dependency vulnerability scanning confirmed in pipeline results

### Code Quality
- [ ] Zero lint errors — backend: `ruff check .` — frontend: `npm run lint`
- [ ] Zero type errors — backend: `mypy .` — frontend: `vue-tsc --noEmit`
- [ ] No bare `except:` clauses in Python
- [ ] No `console.log` / `console.debug` left in frontend code
- [ ] No inline styles in Vue components (except dynamic values)
- [ ] Components under 200 lines, stores under 150 lines, route handlers under 20 lines

### Security (Pipeline)
- [ ] No hardcoded secrets, passwords, API keys, or tokens in any tracked file
- [ ] No `SUPABASE_SERVICE_ROLE_KEY` in frontend code
- [ ] No raw SQL strings — use supabase-py query builder
- [ ] No `eval()` in JavaScript/TypeScript
- [ ] All user input validated (Pydantic on backend, zod on frontend)
- [ ] RLS policies defined for every new database table
- [ ] Gitleaks scan passes with zero findings

### Error Handling (Pipeline)
- [ ] Every async operation has loading, error, and empty states in the UI
- [ ] API errors return standard envelope with correlation ID
- [ ] No stack traces exposed to clients
- [ ] All errors logged server-side with correlation ID

### Data Integrity (Pipeline)
- [ ] Schema changes are in Supabase migrations (not app code)
- [ ] Every table has: id, created_at, updated_at, deleted_at columns
- [ ] Soft deletes used (no hard DELETE)
- [ ] Multi-step writes wrapped in transactions (Supabase RPC)
- [ ] No N+1 queries
- [ ] No `SELECT *`

### Accessibility (Pipeline)
- [ ] All interactive elements have accessible names
- [ ] Form inputs have associated labels
- [ ] Keyboard navigation works for all flows
- [ ] Color contrast meets WCAG AA
- [ ] Images have alt text

### Cleanup
- [ ] No TODO/FIXME markers left in changed files
- [ ] No dead code or unused imports

### Final Gate
- [ ] Opus code review: **APPROVED** or **APPROVED WITH CONDITIONS** (zero blocking issues, all Tier 1 present)
