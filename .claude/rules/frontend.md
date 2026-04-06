---
globs: ["frontend/components/**", "frontend/pages/**", "frontend/composables/**", "frontend/stores/**", "frontend/services/**"]
---

## Design

Every frontend file — pages, components, and layouts — must meet production design quality. Apply these principles automatically; do not wait to be asked.

**Before writing any page or component, commit to a clear aesthetic direction:**
- What problem does this interface solve? Who uses it?
- Pick a tone and execute it with precision: brutally minimal, editorial, luxury/refined, soft/pastel, industrial, retro-futuristic, etc. Intentionality matters more than intensity.
- Each page should have one distinctive visual element — a custom illustration, animated transition, bold typography treatment, or unexpected layout choice.

**Typography** — Choose distinctive, characterful fonts. Pair a display font with a refined body font. Load via Google Fonts or a CDN `<link>`. Never use Inter, Roboto, Arial, or system fonts.

**Color & Theme** — Commit to a cohesive palette with CSS variables. Dominant colors + sharp accents outperform timid, evenly-distributed palettes.

**Motion** — Staggered page-load reveals (`animation-delay`) and hover states that surprise. CSS-only preferred. One well-orchestrated entrance beats scattered micro-interactions.

**Spatial Composition** — Intentional layouts over generic defaults. Use Tailwind's grid and flexbox utilities creatively — asymmetric column ratios (`grid-cols-[2fr_1fr]`), overlapping elements via negative margins or `z-index`, generous whitespace (`py-24`, `gap-16`). Avoid the predictable 12-column center-everything pattern.

**Backgrounds & Depth** — Atmosphere over flat solid colors: Tailwind gradients (`bg-gradient-to-br`), layered `bg-opacity` and `backdrop-blur`, `shadow-2xl` for depth, decorative border/ring accents. Use `<style scoped>` only for effects Tailwind genuinely cannot express (e.g., complex SVG backgrounds, `@keyframes` custom animations).

**Fallback design directions** (when user has no preference): Offer these three options during Discovery or first UI build. If the user doesn't choose, default to "Modern editorial."
1. **Modern editorial** — Serif display font (Playfair Display / DM Serif), generous whitespace, bold type scale, dark accent color
2. **Warm minimal** — Rounded sans-serif (Nunito / Quicksand), soft earth tones, rounded corners (`rounded-2xl`), subtle shadows
3. **Bold industrial** — Mono/geometric sans (JetBrains Mono / Archivo Black), dark backgrounds, sharp edges, bright accent on dark

**NEVER:**
- Generic font families: Inter, Roboto, Arial, Space Grotesk, system fonts
- Clichéd color schemes: purple gradients on white, grey-on-grey monotone
- Predictable card/sidebar/hero layouts with no point of view
- Cookie-cutter components that could belong to any app

Once the aesthetic direction is established for a project, all subsequent components follow the same visual language — do not reinvent it per component, but do execute each one with the same quality bar.

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

- TailwindCSS utilities as the primary styling method. Use `<style scoped>` for effects Tailwind cannot express: complex `@keyframes` animations, SVG background patterns, gradient meshes, and `backdrop-filter` compositions. Keep scoped styles under 30 lines — if longer, extract to a utility class in `tailwind.config.ts`.
- Consistent spacing scale. Responsive: `sm:`, `md:`, `lg:` prefixes.

## Realtime

- Subscribe in composables, not components. Unsubscribe in `onUnmounted`. Handle reconnection. Signed URLs < 1hr.

## CSRF

- JWT-based auth (Supabase mode): No CSRF protection needed — tokens are sent via Authorization header, not cookies
- Cookie-based auth (Azure OAuth2 Proxy mode): Proxy handles CSRF via SameSite cookies. For custom forms that POST to non-API endpoints, validate `Origin` header server-side
- Never set `SameSite=None` on auth-related cookies
