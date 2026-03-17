---
globs: ["frontend/components/**", "frontend/pages/**", "frontend/composables/**", "frontend/stores/**", "frontend/services/**"]
---

## Service Layer

- Route all data access through `frontend/services/`. Services encapsulate Supabase queries, auth, storage. Components call services and receive typed responses.

## Pinia Stores

- Mutate state through actions only — never directly from components
- Getters are pure computed values — no API calls, no side effects, no async
- Split by domain, < 150 lines each
- Subscribe to Realtime in composables, update stores from there

## Async State Management

Every async operation needs loading, error, and empty states. Loading: skeleton/spinner. Error: user-friendly message + retry. Empty: meaningful message. Never show stale data without indicating it.

## Component Structure

- < 200 lines; split if bigger. Composition API with `<script setup lang="ts">`.
- Type props with `defineProps<{...}>()`, emits with `defineEmits<{...}>()`.
- Extract reusable logic into composables.

## Accessibility

- Accessible name on every interactive element. Label on every form input.
- Keyboard navigation (Tab, Enter, Escape). Color never sole information carrier.
- Contrast: 4.5:1 normal, 3:1 large (WCAG AA). Alt text on images (`alt=""` for decorative).
- Keep focus visible.

## Styling

- TailwindCSS utilities only (no inline styles except dynamic values). Avoid `<style scoped>` unless Tailwind can't express it.
- Consistent spacing scale. Responsive: `sm:`, `md:`, `lg:` prefixes.

## Realtime

- Subscribe in composables, not components. Unsubscribe in `onUnmounted`. Handle reconnection. Signed URLs < 1hr.

## CSRF

- JWT-based auth (Supabase mode): No CSRF protection needed — tokens are sent via Authorization header, not cookies
- Cookie-based auth (Azure OAuth2 Proxy mode): Proxy handles CSRF via SameSite cookies. For custom forms that POST to non-API endpoints, validate `Origin` header server-side
- Never set `SameSite=None` on auth-related cookies
