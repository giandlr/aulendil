---
globs: ["frontend/components/**", "frontend/app/**", "frontend/hooks/**", "frontend/stores/**", "frontend/services/**"]
---

# Next.js / React Frontend Conventions

**Applies when:** `FRONTEND_FRAMEWORK=next` in `.env`. For Vue/Nuxt conventions, see `frontend.md`.

## Design

All design rules from `frontend.md` apply identically — Typography, Color & Theme, Motion, Spatial Composition, Backgrounds & Depth, fallback design directions, and the NEVER list. This file covers React/Next.js-specific conventions only.

## Service Layer

- Route all data access through `frontend/services/`. Services encapsulate Supabase queries, auth, storage. Components call services and receive typed responses.

## Zustand Stores

- One store per domain, < 150 lines each
- Mutate state through actions only — never directly from components
- Selectors for derived state — pure functions, no API calls, no side effects
- Split by domain using `create()` from zustand
- Subscribe to Realtime in custom hooks, update stores from there

## Async State Management

Every async operation needs loading, error, and empty states. Loading: skeleton/spinner. Error: user-friendly message + retry. Empty: meaningful message. Never show stale data without indicating it.

## Component Structure

- < 200 lines; split if bigger. Function components with TypeScript.
- Props typed with TypeScript interfaces. Events via callback props.
- Extract reusable logic into custom hooks (`frontend/hooks/`).
- Use `'use client'` directive only when component needs browser APIs, state, or effects.

## Forms

- React Hook Form + `@hookform/resolvers` + zod for all forms
- Define schemas in `frontend/types/` or co-located with the form
- Use `useForm()` with `zodResolver(schema)`
- Display inline validation errors below each field

## Routing

- App Router (`frontend/app/`) with file-based routing
- `page.tsx` for routes, `layout.tsx` for shared layouts
- `loading.tsx` for loading states, `error.tsx` for error boundaries
- `middleware.ts` at project root for auth redirect guards

## Auth

- Zustand auth store + custom `useAuth` hook
- `middleware.ts` checks session and redirects unauthenticated users to `/login`
- Session state synced via `onAuthStateChange` in a root-level provider
- Environment prefix: `NEXT_PUBLIC_*` for client-side variables

## Accessibility

- Accessible name on every interactive element. Label on every form input.
- Keyboard navigation (Tab, Enter, Escape). Color never sole information carrier.
- Contrast: 4.5:1 normal, 3:1 large (WCAG AA). Alt text on images (`alt=""` for decorative).
- Keep focus visible.

## Styling

- TailwindCSS utilities as the primary styling method.
- Use CSS Modules (`.module.css`) for effects Tailwind cannot express: complex `@keyframes` animations, SVG background patterns, gradient meshes.
- Keep module styles under 30 lines — if longer, extract to a utility class in `tailwind.config.ts`.
- Consistent spacing scale. Responsive: `sm:`, `md:`, `lg:` prefixes.

## Realtime

- Subscribe in custom hooks, not components. Clean up in `useEffect` return. Handle reconnection. Signed URLs < 1hr.

## CSRF

- No CSRF protection needed — authentication uses Bearer tokens in the Authorization header, not cookies.

## Testing

- **Unit/Component:** Vitest + @testing-library/react + @testing-library/jest-dom
- **E2E:** Playwright (same setup as Nuxt projects)
- Test files in `frontend/tests/` or co-located as `*.test.tsx`

## Blocks

- Direct Supabase calls outside `services/`
- `SUPABASE_SERVICE_ROLE_KEY` in any frontend file
- `useEffect` with missing dependency arrays
- Inline styles (except dynamic computed values)
