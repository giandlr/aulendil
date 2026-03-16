#!/usr/bin/env bash
set -uo pipefail

# Scaffold Flutter mobile app into mobile/ directory
# Usage: bash .claude/scripts/scaffold-flutter-mobile.sh
# Triggered automatically by bootstrap.sh when INCLUDE_MOBILE=true
# Exit 0 = success (scaffold created or already exists)
# Exit 0 = graceful skip (Flutter not installed — warns but does not fail)

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
AUDIT_LOG=".claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
echo "[$TIMESTAMP] scaffold-flutter-mobile: started" >> "$AUDIT_LOG"

echo "=========================================================="
echo " SCAFFOLD FLUTTER MOBILE"
echo "=========================================================="
echo ""

APP_NAME="${APP_NAME:-$(basename "$(pwd)" | tr '-' '_' | tr '[:upper:]' '[:lower:]')}"
APP_DART="${APP_NAME//-/_}"

echo "  App name: $APP_NAME"
echo ""

# ----------------------------------------------------------
# Preflight: Flutter must be installed
# ----------------------------------------------------------
if ! command -v flutter &>/dev/null; then
    echo "  WARNING: Flutter not installed — mobile scaffold skipped."
    echo "           Install Flutter from https://flutter.dev/docs/get-started/install"
    echo "           then re-run: bash .claude/scripts/scaffold-flutter-mobile.sh"
    echo ""
    echo "[$TIMESTAMP] scaffold-flutter-mobile: skipped (flutter not found)" >> "$AUDIT_LOG"
    exit 0
fi

FLUTTER_VERSION=$(flutter --version 2>/dev/null | head -1 || echo "unknown")
echo "  Flutter: $FLUTTER_VERSION"
echo ""

# ----------------------------------------------------------
# Idempotency: skip if mobile/ already scaffolded
# ----------------------------------------------------------
if [[ -f "mobile/pubspec.yaml" ]]; then
    echo "  mobile/ already exists — skipping scaffold"
    echo "[$TIMESTAMP] scaffold-flutter-mobile: skipped (already exists)" >> "$AUDIT_LOG"
    exit 0
fi

# ----------------------------------------------------------
# Create Flutter project
# ----------------------------------------------------------
echo "  Creating Flutter project..."
flutter create \
    --org "com.example" \
    --project-name "$APP_DART" \
    --platforms ios,android \
    mobile 2>&1 | tail -5

echo "  + Created mobile/ via flutter create"

# ----------------------------------------------------------
# Build directory structure per mobile.md conventions
# ----------------------------------------------------------
mkdir -p \
    "mobile/lib/features/.keep" \
    "mobile/lib/core/services" \
    "mobile/lib/core/auth" \
    "mobile/lib/core/router" \
    "mobile/lib/shared" \
    "mobile/test" \
    "mobile/integration_test"

echo "  + Created feature directory structure"

# ----------------------------------------------------------
# Add required dependencies
# ----------------------------------------------------------
echo ""
echo "  Adding dependencies..."
cd mobile

flutter pub add \
    supabase_flutter \
    go_router \
    riverpod \
    flutter_riverpod \
    riverpod_annotation \
    2>&1 | tail -5

flutter pub add --dev \
    riverpod_generator \
    build_runner \
    mocktail \
    integration_test \
    flutter_test \
    2>&1 | tail -5

echo "  + Dependencies added"
cd ..

# ----------------------------------------------------------
# Write core files
# ----------------------------------------------------------

# main.dart
cat > mobile/lib/main.dart << 'DARTEOF'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  runApp(const ProviderScope(child: App()));
}
DARTEOF
echo "  + Created lib/main.dart"

# app.dart
cat > mobile/lib/app.dart << 'DARTEOF'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/router.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'App',
      routerConfig: router,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
    );
  }
}
DARTEOF
echo "  + Created lib/app.dart"

# core/router/router.dart
cat > mobile/lib/core/router/router.dart << 'DARTEOF'
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'router.g.dart';

@riverpod
GoRouter router(RouterRef ref) {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Home')),
        ),
      ),
    ],
  );
}
DARTEOF
echo "  + Created lib/core/router/router.dart"

# core/auth/auth_provider.dart
cat > mobile/lib/core/auth/auth_provider.dart << 'DARTEOF'
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'auth_provider.g.dart';

@riverpod
Stream<AuthState> authState(AuthStateRef ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
}

@riverpod
User? currentUser(CurrentUserRef ref) {
  return Supabase.instance.client.auth.currentUser;
}
DARTEOF
echo "  + Created lib/core/auth/auth_provider.dart"

# core/services/supabase_service.dart
cat > mobile/lib/core/services/supabase_service.dart << 'DARTEOF'
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared Supabase client accessor.
/// Feature repositories import this — never call Supabase directly from
/// presentation/ or domain/ layers.
SupabaseClient get supabase => Supabase.instance.client;
DARTEOF
echo "  + Created lib/core/services/supabase_service.dart"

# .gitignore additions for Flutter
cat >> mobile/.gitignore << 'GITEOF'

# Build runner outputs
*.g.dart
*.freezed.dart
GITEOF

echo ""
echo "=========================================================="
echo " Flutter mobile scaffold complete"
echo "=========================================================="
echo ""
echo "  Directory layout:"
echo "    mobile/lib/features/        Feature modules (data/domain/presentation)"
echo "    mobile/lib/core/            Auth, router, shared services"
echo "    mobile/lib/shared/          Common widgets, theme, constants"
echo "    mobile/test/                Unit + widget tests"
echo "    mobile/integration_test/    Full app integration tests"
echo ""
echo "  Next steps:"
echo "    cd mobile && dart run build_runner build   # Generate Riverpod providers"
echo "    cd mobile && flutter run                   # Run on device/simulator"
echo "    cd mobile && flutter test --coverage       # Run tests"
echo ""
echo "  See .claude/rules/mobile.md for coding conventions."
echo ""

echo "[$TIMESTAMP] scaffold-flutter-mobile: completed" >> "$AUDIT_LOG"
exit 0
