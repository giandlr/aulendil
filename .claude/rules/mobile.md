# Flutter Mobile Conventions

These rules apply to the `mobile/` directory whenever it is present.

## Service Layer

- **BLOCK:** Direct `supabase` or `dio` calls outside `features/*/data/` or `core/services/`.
  All Supabase queries and HTTP calls belong in repository classes inside `features/[feature]/data/`.

## State Management

- **BLOCK:** `setState` inside a screen widget that has a Riverpod provider.
  Use `ref.watch` / `ref.read` instead — `setState` in provider-driven screens causes double rebuilds.
- Use `@riverpod` code-gen annotations (`riverpod_generator`). Run `dart run build_runner watch` to keep providers fresh.
- Providers live in `features/[feature]/domain/`. Business logic stays there, not in `presentation/`.

## Auth

- Auth state lives in `core/auth/auth_provider.dart` using `supabase_flutter`'s session stream.
- `GoRouter` redirect guard reads the auth provider — never check `supabase.auth.currentUser` inline inside a widget.
- On logout, call `supabase.auth.signOut()` then let the router redirect.

## Navigation

- All routes declared in `core/router/router.dart` using `go_router`.
- Use `context.go()` / `context.push()` — never `Navigator.push` directly.
- Pass typed route parameters via `GoRoute` `extra` or path params.

## Component Structure

- Screen widget file limit: **200 lines**. Split into sub-widgets or composable widget files if exceeded.
- **WARN:** Screen widget over 200 lines — extract sub-widgets into `presentation/widgets/`.
- Widgets that hold no logic should be `const` constructors.

## Testing

- Unit tests for providers and repositories in `test/`.
- Widget tests for screens and complex widgets in `test/`.
- Integration tests (full app boot + Supabase) in `integration_test/`.
- Mock Supabase using `mocktail` — never hit a real Supabase project from unit/widget tests.
- Every provider or repository file needs a corresponding test file.

## Lint / Format

- `flutter analyze` must pass with zero issues before every commit.
- `dart format --set-exit-if-changed .` enforces consistent style.

## Dev Commands

```
cd mobile && flutter run                              # Run on connected device/simulator
cd mobile && flutter test --coverage                 # Unit + widget tests
cd mobile && flutter test integration_test/          # Integration tests
cd mobile && flutter analyze && dart format --set-exit-if-changed .   # Lint + format
```

## Directory Contract

```
mobile/
├── lib/
│   ├── main.dart                   # Entry point — calls runApp(ProviderScope(child: App()))
│   ├── app.dart                    # MaterialApp.router with GoRouter
│   ├── features/
│   │   └── [feature]/
│   │       ├── data/               # Repository + Supabase/Dio calls ONLY here
│   │       ├── domain/             # Riverpod providers + business logic
│   │       └── presentation/       # Screens + widgets (< 200 lines each)
│   ├── core/
│   │   ├── services/               # Shared Supabase service wrapper
│   │   ├── auth/                   # Auth provider (supabase_flutter session)
│   │   └── router/                 # go_router config
│   └── shared/                     # Common widgets, constants, theme
├── test/
├── integration_test/
└── pubspec.yaml
```

## What to Enforce Automatically

BLOCK:
- Direct `supabase.*` or `Dio.*` call inside `presentation/` or `domain/`
- `setState` in a screen that imports a Riverpod `ref`

WARN:
- Screen widget over 200 lines
- Any TODO/FIXME left in changed files
