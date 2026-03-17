# Flutter Mobile Conventions

**Applies to:** `mobile/` directory when present. Full spec: `.claude/refs/mobile.md` — read it before writing mobile code.

**Key rules (always enforced):**
- BLOCK: Direct `supabase`/`Dio` calls outside `features/*/data/` or `core/services/`
- BLOCK: `setState` in a screen that imports a Riverpod `ref`
- All state via `@riverpod` code-gen; screens < 200 lines
- Auth in `core/auth/`, routing in `core/router/` via `go_router`
- Tests: `mocktail` for mocks, never hit real Supabase from unit tests
