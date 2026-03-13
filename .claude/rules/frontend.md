---
globs: ["frontend/components/**", "frontend/pages/**", "frontend/composables/**", "frontend/stores/**", "frontend/services/**"]
---

> **Tone:** Apply these patterns automatically during build. Narrate briefly in plain English what you included and why.

## Service Layer Requirement

- Always route data access through `frontend/services/`. Narrate: "I put the data call in the service layer so the component stays clean."
- Services encapsulate all Supabase queries, auth calls, and storage operations.
- Components call service functions and receive typed responses.
- This separation allows swapping the backend without changing components.

## Pinia Store Rules

- Always mutate state through actions — never directly from components (`store.count++` is forbidden, use `store.increment()`). Narrate: "I used a store action to update the state so changes are trackable."
- Always keep getters as pure computed values — no API calls, no side effects, no async operations.
- API calls belong in actions, not getters.
- Split stores by domain — keep each store under 150 lines.
- Subscribe to Supabase Realtime in composables, update stores from there.

## Async State Management

Always include loading, error, and empty states for async operations. Narrate: "I added a loading spinner, error message, and empty state so users always know what's happening."

- **Loading:** Show a skeleton or spinner while data is being fetched.
- **Error:** Show a user-friendly error message with a retry option.
- **Empty:** Show a meaningful empty state (not just blank space).

Never show stale data without indicating it is stale. Never leave the user guessing.

## Component Size and Structure

- Keep components under 200 lines. If a component gets bigger, split it automatically and narrate: "I split this into smaller components to keep things manageable."
- Always use Composition API with `<script setup lang="ts">`. Narrate: "I used the standard script setup format."
- Always type props with `defineProps<{...}>()` and emits with `defineEmits<{...}>()`.
- Extract reusable logic into composables in `frontend/composables/`. Narrate: "I pulled the shared logic into a composable so it can be reused."

## Accessibility

Always include accessibility features automatically. Narrate: "I added accessibility support so the app works for everyone."

- Always give every interactive element an accessible name (aria-label, aria-labelledby, or visible text).
- Always associate every form input with a `<label>` element.
- Always ensure keyboard navigation works for all interactive flows (Tab, Enter, Escape).
- Never use color as the only way to convey information — always include icons, text, or patterns alongside color.
- Minimum color contrast ratio: 4.5:1 for normal text, 3:1 for large text (WCAG AA).
- Always include alt text on images — use `alt=""` for decorative images.
- Always keep focus visible — never remove outline without providing an alternative focus indicator.

## Styling Rules

- Always use TailwindCSS utility classes — no inline styles except for truly dynamic values (calculated positions, runtime colors). Narrate: "I used Tailwind classes for styling."
- Avoid `<style scoped>` blocks with raw CSS unless TailwindCSS cannot express the style.
- Follow a consistent spacing scale — use Tailwind's spacing utilities, not arbitrary pixel values.
- Always include responsive design — use Tailwind's responsive prefixes (`sm:`, `md:`, `lg:`). Narrate: "I made it responsive so it works on phones and desktops."

## Supabase Realtime in Components

- Always subscribe to Realtime channels in composables, not directly in components. Narrate: "I set up the live updates in a composable so it's reusable."
- Always unsubscribe in `onUnmounted` to prevent memory leaks.
- Always handle reconnection gracefully — Realtime connections can drop.
- Never expose signed URLs longer than 1 hour for Supabase Storage.
