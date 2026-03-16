# Mobile Architecture

## Overview

When `INCLUDE_MOBILE=true` is set (or the user selects "Mobile app" in Discovery Mode), Aulendil scaffolds a `mobile/` Flutter directory alongside the existing web frontend. The mobile app connects to the **same Supabase backend** and optional FastAPI / ASP.NET Core API, sharing auth, data, and realtime features.

```
┌─────────────────┐   ┌─────────────────┐
│  Nuxt 3 Web     │   │  Flutter Mobile  │
│  (frontend/)    │   │  (mobile/)       │
│                 │   │                  │
│  Supabase JS ──────────supabase_flutter│
│  (anon key)     │   │  (anon key)      │
│                 │   │                  │
│  REST → FastAPI │   │  REST → FastAPI  │
│  or C# backend  │   │  or C# backend   │
└────────┬────────┘   └────────┬─────────┘
         │                     │
         └──────────┬──────────┘
                    ▼
         ┌─────────────────────┐
         │     Supabase        │
         │  PostgreSQL + RLS   │
         │  Auth (JWT)         │
         │  Storage            │
         │  Realtime           │
         └─────────────────────┘
```

## Flutter Stack

| Concern | Library | Why |
|---------|---------|-----|
| State | Riverpod 2.x (`riverpod_generator`) | Compile-safe, testable, no BuildContext needed |
| HTTP | Dio | Interceptors for JWT injection, retry, logging |
| Supabase | `supabase_flutter` | Official SDK — handles auth session, storage, realtime |
| Navigation | `go_router` | Declarative, deep-link ready, typed routes |
| Testing | `flutter_test` + `mocktail` + `integration_test` | Full test pyramid |
| Lint/Format | `flutter analyze` + `dart format` | Enforced in pipeline |

## Feature-First Directory Structure

```
mobile/
├── lib/
│   ├── main.dart                    # runApp(ProviderScope(child: App()))
│   ├── app.dart                     # MaterialApp.router
│   ├── features/                    # Feature-first organisation
│   │   └── [feature]/
│   │       ├── data/                # Repository + all Supabase/Dio calls
│   │       ├── domain/              # Riverpod providers + business logic
│   │       └── presentation/        # Screens + widgets (< 200 lines each)
│   ├── core/
│   │   ├── services/                # Shared Supabase wrapper (init, headers)
│   │   ├── auth/                    # Auth Riverpod provider (session stream)
│   │   └── router/                  # go_router config + auth redirect guard
│   └── shared/                      # Common widgets, constants, theme tokens
├── test/                            # Unit + widget tests
├── integration_test/                # Full-app integration tests
└── pubspec.yaml
```

## Auth Flow

1. `core/auth/auth_provider.dart` listens to `supabase.auth.onAuthStateChange`.
2. `GoRouter` redirect guard checks auth state — unauthenticated users go to `/login`.
3. Supabase session (JWT + refresh token) is persisted in secure storage by `supabase_flutter`.
4. All API calls add `Authorization: Bearer <access_token>` via a Dio interceptor.
5. Backend verifies JWT identically to the web path — same Supabase Auth, same RLS.

## Realtime

Subscribe to Supabase channels in feature providers (`domain/`), not in widgets. Unsubscribe in the provider's `onDispose`.

```dart
@riverpod
Stream<List<Item>> itemsStream(ItemsStreamRef ref) {
  final channel = supabase.channel('items');
  // ... subscribe
  ref.onDispose(() => channel.unsubscribe());
  return stream;
}
```

## Deployment

- **iOS:** Build with `flutter build ipa`, distribute via TestFlight (staging) or App Store.
- **Android:** Build with `flutter build appbundle`, distribute via Google Play.
- The mobile app points to the same backend URL as the web frontend — no separate infra needed.
- Environment: `--dart-define=SUPABASE_URL=...` at build time or `flutter_dotenv` for `.env` loading.

## Environment Variables (Mobile)

| Variable | Where Set | Description |
|----------|-----------|-------------|
| `SUPABASE_URL` | `--dart-define` or `.env` | Supabase project URL |
| `SUPABASE_ANON_KEY` | `--dart-define` or `.env` | Public API key (respects RLS) |
| `API_BASE_URL` | `--dart-define` or `.env` | FastAPI / C# backend base URL |

## Testing Strategy

| Layer | Tool | What It Tests |
|-------|------|---------------|
| Unit | `flutter_test` + `mocktail` | Providers, repositories, business logic |
| Widget | `flutter_test` | Screen rendering, interactions |
| Integration | `integration_test` | Full app boot, real Supabase test project |

Run all tests: `cd mobile && flutter test --coverage`
