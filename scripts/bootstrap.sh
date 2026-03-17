#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Bootstrap — From empty directory to running app
#
# Usage: bash scripts/bootstrap.sh
#
# This script:
#   1. Scaffolds Nuxt 3 frontend + FastAPI backend + Supabase
#   2. Installs all dependencies and dev tools
#   3. Starts local Supabase, backend, and frontend
#   4. Prints the URL where your app is running
#
# Run from your project root after install.sh has copied
# the toolkit files.
# ─────────────────────────────────────────────────────────────

# ============================================================
# Detect platform
# ============================================================
OS_TYPE="unknown"
case "$(uname -s)" in
    Darwin*)  OS_TYPE="macos" ;;
    Linux*)
        if grep -qi microsoft /proc/version 2>/dev/null; then
            OS_TYPE="wsl"
        else
            OS_TYPE="linux"
        fi
        ;;
    MINGW*|MSYS*|CYGWIN*) OS_TYPE="windows" ;;
esac

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " BOOTSTRAP"
echo " $(date '+%Y-%m-%d %H:%M:%S')  |  Platform: $OS_TYPE"
echo "═══════════════════════════════════════════════════════════"
echo ""

INSTALLED=()
WARNINGS=()

# Helper: install a package using the appropriate system package manager
sys_install() {
    local pkg="$1"
    local tap="${2:-}"

    if [[ "$OS_TYPE" == "macos" ]] && command -v brew &>/dev/null; then
        [[ -n "$tap" ]] && brew install "$tap" 2>&1 | tail -3 || brew install "$pkg" 2>&1 | tail -3
        return $?
    elif [[ "$OS_TYPE" == "windows" || "$OS_TYPE" == "wsl" || "$OS_TYPE" == "linux" ]]; then
        if command -v winget &>/dev/null; then
            winget install --id "$pkg" --accept-package-agreements --accept-source-agreements 2>&1 | tail -3
            return $?
        elif command -v choco &>/dev/null; then
            choco install "$pkg" -y 2>&1 | tail -3
            return $?
        elif command -v scoop &>/dev/null; then
            scoop install "$pkg" 2>&1 | tail -3
            return $?
        elif command -v apt-get &>/dev/null; then
            sudo apt-get install -y "$pkg" 2>&1 | tail -3
            return $?
        fi
    fi
    return 1
}

# Helper: wait for a URL to respond (max 30 seconds)
wait_for_url() {
    local url="$1"
    local label="$2"
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -qE "^[23]"; then
            echo "  $label is ready at $url"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    WARNINGS+=("$label did not respond at $url within 30 seconds")
    return 1
}

# ============================================================
# Pre-flight checks
# ============================================================

echo "Checking prerequisites..."

# Node.js
if ! command -v node &>/dev/null; then
    echo "  ERROR: Node.js is required but not installed."
    echo "  Install from: https://nodejs.org/"
    exit 1
fi
echo "  Node.js $(node --version)"

# npm
if ! command -v npm &>/dev/null; then
    echo "  ERROR: npm is required but not installed."
    exit 1
fi
echo "  npm $(npm --version)"

# Python
PYTHON_CMD=""
if command -v python3 &>/dev/null; then
    PYTHON_CMD="python3"
elif command -v python &>/dev/null; then
    PYTHON_CMD="python"
else
    echo "  ERROR: Python 3.9+ is required but not installed."
    echo "  Install from: https://python.org/"
    exit 1
fi
echo "  Python $($PYTHON_CMD --version 2>&1 | sed 's/Python //')"

# pip
PIP_CMD=""
if command -v pip3 &>/dev/null; then
    PIP_CMD="pip3"
elif command -v pip &>/dev/null; then
    PIP_CMD="pip"
else
    echo "  ERROR: pip is required but not installed."
    exit 1
fi

# Docker (needed for Supabase local)
if ! command -v docker &>/dev/null; then
    WARNINGS+=("Docker not found — Supabase local requires Docker. Install from https://docker.com/")
fi

echo ""

# ============================================================
# Read stack selection from .env (set by Claude during Discovery)
# ============================================================

BACKEND_LANGUAGE="python"
INCLUDE_MOBILE="false"

if [ -f ".env" ]; then
    _bl=$(grep -E "^BACKEND_LANGUAGE=" .env 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"' | tr -d "'")
    [ -n "$_bl" ] && BACKEND_LANGUAGE="$_bl"
    _im=$(grep -E "^INCLUDE_MOBILE=" .env 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"' | tr -d "'")
    [ -n "$_im" ] && INCLUDE_MOBILE="$_im"
fi

echo "  Backend:  $BACKEND_LANGUAGE"
echo "  Mobile:   $INCLUDE_MOBILE"
echo ""

# ============================================================
# Phase 1: Scaffold
# ============================================================

echo "───────────────────────────────────────────────────────────"
echo " Phase 1: Scaffold"
echo "───────────────────────────────────────────────────────────"
echo ""

# Frontend — Nuxt 3
if [ ! -d "frontend" ]; then
    echo "  Creating Nuxt 3 frontend..."
    mkdir -p frontend
    cat > frontend/package.json << 'PKGEOF'
{
  "name": "frontend",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "nuxt build",
    "dev": "nuxt dev",
    "generate": "nuxt generate",
    "preview": "nuxt preview",
    "postinstall": "nuxt prepare"
  },
  "dependencies": {
    "nuxt": "^3.14.0",
    "vue": "^3.5.0",
    "vue-router": "^4.4.0"
  }
}
PKGEOF
    echo "  Created frontend/"
else
    echo "  frontend/ already exists — skipping scaffold"
fi

# Frontend directories
echo "  Creating frontend directories..."
for dir in components composables pages stores services types tests; do
    mkdir -p "frontend/$dir"
done
echo "  Created: components, composables, pages, stores, services, types, tests"

# Backend — FastAPI
if [ ! -d "backend" ]; then
    echo "  Creating FastAPI backend..."
    mkdir -p backend/{routes,services,models,middleware,tests}

    # main.py
    cat > backend/main.py << 'PYEOF'
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(
    title=os.getenv("APP_NAME", "Aulendil"),
    version="0.1.0",
)

# CORS — allow frontend dev server
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:3000",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    return {"status": "ok"}
PYEOF

    # requirements.txt
    cat > backend/requirements.txt << 'REQEOF'
fastapi>=0.104.0
uvicorn[standard]>=0.24.0
supabase>=2.0.0
python-dotenv>=1.0.0
pydantic>=2.0.0
httpx>=0.25.0
REQEOF

    # Dev requirements
    cat > backend/requirements-dev.txt << 'REQEOF'
ruff>=0.1.0
mypy>=1.7.0
bandit>=1.7.0
pip-audit>=2.6.0
pytest>=7.4.0
pytest-cov>=4.1.0
pytest-asyncio>=0.23.0
httpx>=0.25.0
REQEOF

    # __init__.py files
    for dir in routes services models middleware tests; do
        touch "backend/$dir/__init__.py"
    done

    # conftest.py
    cat > backend/tests/conftest.py << 'PYEOF'
import pytest
from httpx import AsyncClient, ASGITransport
from main import app


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
PYEOF

    # Integration tests scaffold
    mkdir -p backend/tests/integration
    touch backend/tests/integration/__init__.py

    cat > backend/tests/integration/conftest.py << 'PYEOF'
import pytest
from httpx import AsyncClient, ASGITransport
from main import app


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
PYEOF

    cat > backend/tests/integration/test_api_health.py << 'PYEOF'
import pytest


@pytest.mark.anyio
async def test_health(client):
    response = await client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
PYEOF

    echo "  Created backend/ with main.py, requirements, and directory structure"
else
    echo "  backend/ already exists — skipping scaffold"
fi

# C# backend scaffold (only when BACKEND_LANGUAGE=csharp and backend/ not yet present)
if [ "$BACKEND_LANGUAGE" = "csharp" ] && [ ! -f "backend/backend.csproj" ]; then
    echo "  Switching to C# backend scaffold..."
    if [ -f ".claude/scripts/scaffold-csharp-backend.sh" ]; then
        bash .claude/scripts/scaffold-csharp-backend.sh
    else
        echo "  WARNING: scaffold-csharp-backend.sh not found — skipping C# scaffold"
    fi
fi

# Mobile — Flutter (only when INCLUDE_MOBILE=true and mobile/ not yet present)
if [ "$INCLUDE_MOBILE" = "true" ] && [ ! -d "mobile" ]; then
    echo "  Scaffolding Flutter mobile app..."
    if command -v flutter &>/dev/null; then
        flutter create --org com.example --project-name mobile mobile 2>&1 | tail -5
        mkdir -p mobile/lib/{features,core/{services,auth,router},shared}
        mkdir -p mobile/integration_test
        echo "  Created mobile/ (Flutter project)"
        INSTALLED+=("Flutter mobile scaffold")
    else
        echo "  WARNING: flutter not found — install Flutter SDK from https://flutter.dev/docs/get-started/install"
        WARNINGS+=("Flutter not installed — mobile/ not scaffolded. Install from https://flutter.dev/docs/get-started/install")
        INCLUDE_MOBILE="false"
    fi
fi

# Supabase directory
echo "  Creating Supabase directories..."
mkdir -p supabase/migrations
mkdir -p supabase/functions
echo "  Created supabase/migrations and supabase/functions"

# Create RBAC migration (roles + user_roles tables)
if [ ! -f "supabase/migrations/00000000000001_rbac.sql" ]; then
    cat > supabase/migrations/00000000000001_rbac.sql << 'SQLEOF'
-- RBAC Foundation: roles and user_roles tables
-- Applied automatically by bootstrap. Do not modify — create new migrations instead.

-- Roles table
CREATE TABLE IF NOT EXISTS roles (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text UNIQUE NOT NULL,
  description text,
  permissions jsonb DEFAULT '{}' NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL
);

-- Seed default roles
INSERT INTO roles (name, description, permissions) VALUES
  ('admin', 'Full access to all resources', '{"all": true}'),
  ('manager', 'Can manage team members and resources', '{"manage_team": true, "manage_resources": true}'),
  ('member', 'Standard access to assigned resources', '{"view": true, "edit_own": true}'),
  ('viewer', 'Read-only access', '{"view": true}')
ON CONFLICT (name) DO NOTHING;

-- User-role assignments
CREATE TABLE IF NOT EXISTS user_roles (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  assigned_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now() NOT NULL,
  UNIQUE(user_id, role_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role_id ON user_roles(role_id);

-- RLS on roles table
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read roles" ON roles
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Admins can modify roles" ON roles
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_roles ur
      JOIN roles r ON ur.role_id = r.id
      WHERE ur.user_id = auth.uid() AND r.name = 'admin'
    )
  );

-- RLS on user_roles table
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own roles" ON user_roles
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "Admins can manage all roles" ON user_roles
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_roles ur
      JOIN roles r ON ur.role_id = r.id
      WHERE ur.user_id = auth.uid() AND r.name = 'admin'
    )
  );

-- Helper function: get user role name
CREATE OR REPLACE FUNCTION get_user_role(uid uuid)
RETURNS text AS $$
  SELECT r.name FROM roles r
  JOIN user_roles ur ON r.id = ur.role_id
  WHERE ur.user_id = uid
  LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Updated_at trigger for roles
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_roles_updated_at
  BEFORE UPDATE ON roles
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
SQLEOF
    echo "  Created RBAC migration (supabase/migrations/00000000000001_rbac.sql)"
fi

# Create seed.sql with dev user for local development
if [ ! -f "supabase/seed.sql" ]; then
    cat > supabase/seed.sql << 'SEEDEOF'
-- Dev user for local development: dev@aulendil.local / devpassword123
INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new,
    email_change_token_current, phone, phone_change, phone_change_token,
    reauthentication_token, is_sso_user, is_anonymous
) VALUES (
    'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'dev@aulendil.local',
    crypt('devpassword123', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"Dev User"}'::jsonb,
    now(), now(), '', '', '', '', '', '', '', '', '', false, false
) ON CONFLICT (id) DO NOTHING;
INSERT INTO auth.identities (
    id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at
) VALUES (
    'a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001',
    'dev@aulendil.local', 'email',
    '{"sub":"a0000000-0000-0000-0000-000000000001","email":"dev@aulendil.local"}'::jsonb,
    now(), now(), now()
) ON CONFLICT (provider_id, provider) DO NOTHING;
SEEDEOF
    echo "  Created supabase/seed.sql with dev user (dev@aulendil.local / devpassword123)"
fi

# Append RBAC admin assignment to seed.sql
if [ -f "supabase/seed.sql" ] && ! grep -q "user_roles" supabase/seed.sql 2>/dev/null; then
    cat >> supabase/seed.sql << 'SEEDEOF'

-- Assign admin role to dev user (runs after RBAC migration)
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id
FROM auth.users u, roles r
WHERE u.email = 'dev@aulendil.local' AND r.name = 'admin'
ON CONFLICT (user_id, role_id) DO NOTHING;
SEEDEOF
    echo "  Added admin role assignment to supabase/seed.sql"
fi

# Create app-specific seed placeholder
if [ ! -f "supabase/seed-app.sql" ]; then
    cat > supabase/seed-app.sql << 'SEEDEOF'
-- App-specific seed data
-- Claude will populate this during the Build phase.
-- Run after migrations: supabase db query < supabase/seed-app.sql
SEEDEOF
    echo "  Created supabase/seed-app.sql (placeholder for app seed data)"
fi

echo ""

# ============================================================
# Phase 2: Configure
# ============================================================

echo "───────────────────────────────────────────────────────────"
echo " Phase 2: Configure"
echo "───────────────────────────────────────────────────────────"
echo ""

# -- Frontend configuration --

echo "  Installing frontend dependencies..."
cd frontend

# Install core deps
npm install 2>&1 | tail -5

# Install project dependencies
npm install @supabase/supabase-js @pinia/nuxt pinia 2>&1 | tail -3
npm install @vee-validate/nuxt @vee-validate/zod vee-validate zod@^3.24.0 2>&1 | tail -3
INSTALLED+=("Supabase JS client, Pinia, vee-validate, zod")

# Install Tailwind CSS
npm install -D tailwindcss @tailwindcss/vite 2>&1 | tail -3
INSTALLED+=("TailwindCSS")

# Install dev tools
npm install -D eslint @typescript-eslint/parser @typescript-eslint/eslint-plugin 2>&1 | tail -3
npm install -D prettier eslint-config-prettier 2>&1 | tail -3
npm install -D vue-tsc typescript 2>&1 | tail -3
npm install -D vitest @vue/test-utils happy-dom 2>&1 | tail -3
INSTALLED+=("ESLint, Prettier, vue-tsc, Vitest")

# Install Playwright for e2e testing
npm install -D @playwright/test @axe-core/playwright 2>&1 | tail -3
npx playwright install chromium 2>&1 | tail -5
INSTALLED+=("Playwright (e2e testing)")

# Create/update nuxt.config.ts
cat > nuxt.config.ts << 'NUXTEOF'
import tailwindcss from "@tailwindcss/vite";

export default defineNuxtConfig({
  compatibilityDate: "2024-11-01",
  devtools: { enabled: false },

  modules: [
    "@pinia/nuxt",
  ],

  css: ["~/assets/css/main.css"],
  vite: {
    plugins: [tailwindcss()],
  },

  runtimeConfig: {
    // Server-only (never exposed to client)
    supabaseServiceRoleKey: "",
    // Public (exposed to client)
    public: {
      supabaseUrl: "",
      supabaseAnonKey: "",
      apiBaseUrl: "http://localhost:8000",
    },
  },

  typescript: {
    strict: true,
  },
});
NUXTEOF

# Create root tsconfig.json extending Nuxt-generated types
cat > tsconfig.json << 'TSCEOF'
{ "extends": "./.nuxt/tsconfig.json" }
TSCEOF

# Create base CSS with Tailwind import
mkdir -p assets/css
cat > assets/css/main.css << 'CSSEOF'
@import "tailwindcss";
CSSEOF

# Create app.vue with nav shell and info banner for missing database
cat > app.vue << 'VUEEOF'
<script setup lang="ts">
const envMissing = useState<string[]>('envMissing', () => [])
</script>

<template>
  <div class="min-h-screen bg-gray-950 text-gray-100">
    <!-- Info banner: shows when Supabase isn't connected yet -->
    <div
      v-if="envMissing.length > 0"
      class="border-b border-blue-800/50 bg-blue-950/40 px-4 py-2 text-center text-sm text-blue-300"
      role="status"
    >
      Running without a database &mdash; your UI is ready, data will show up once you connect Supabase.
    </div>

    <nav class="sticky top-0 z-50 border-b border-gray-800 bg-gray-950/80 backdrop-blur-sm">
      <div class="flex items-center justify-between max-w-7xl mx-auto px-6 h-14">
        <NuxtLink to="/" class="text-lg font-semibold text-white">
          Aulendil
        </NuxtLink>
        <div class="flex items-center gap-4">
          <NuxtLink to="/" class="text-sm text-gray-400 hover:text-gray-200">
            Home
          </NuxtLink>
        </div>
      </div>
    </nav>
    <main class="max-w-7xl mx-auto px-6 py-8">
      <NuxtPage />
    </main>
  </div>
</template>
VUEEOF

# Create index page
cat > pages/index.vue << 'VUEEOF'
<script setup lang="ts">
</script>

<template>
  <div class="text-center py-20">
    <h1 class="text-4xl font-bold text-gray-900 mb-4">
      Welcome to Your App
    </h1>
    <p class="text-lg text-gray-600">
      Start building by describing what you want to Claude Code.
    </p>
  </div>
</template>
VUEEOF

# Create Supabase service client
cat > services/supabase.ts << 'TSEOF'
import { createClient } from "@supabase/supabase-js";

let supabaseInstance: ReturnType<typeof createClient> | null = null;

export function useSupabaseClient() {
  if (supabaseInstance) return supabaseInstance;

  const config = useRuntimeConfig();
  const supabaseUrl = config.public.supabaseUrl as string;
  const supabaseAnonKey = config.public.supabaseAnonKey as string;

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error(
      "Supabase URL and Anon Key must be set in environment variables"
    );
  }

  supabaseInstance = createClient(supabaseUrl, supabaseAnonKey);
  return supabaseInstance;
}
TSEOF

# Create plugins directory
mkdir -p plugins

# Create env-check plugin (graceful degradation when Supabase isn't configured)
cat > plugins/env-check.ts << 'PLUGINEOF'
export default defineNuxtPlugin(() => {
  const config = useRuntimeConfig()
  const missing: string[] = []

  if (!config.public.supabaseUrl) missing.push('NUXT_PUBLIC_SUPABASE_URL')
  if (!config.public.supabaseAnonKey) missing.push('NUXT_PUBLIC_SUPABASE_ANON_KEY')

  const envMissing = useState<string[]>('envMissing', () => missing)

  if (missing.length > 0) {
    envMissing.value = missing
    console.warn(`[Aulendil] Missing environment variables: ${missing.join(', ')}. The app will work without a database — data will appear once you connect Supabase.`)
  }
})
PLUGINEOF

# Create dev-auth plugin (auto-login with seeded dev user in development)
cat > plugins/dev-auth.client.ts << 'PLUGINEOF'
export default defineNuxtPlugin(async () => {
  if (import.meta.dev) {
    const { useSupabaseClient } = await import('~/services/supabase')
    const client = useSupabaseClient()
    if (!client) return

    const { data: { session } } = await client.auth.getSession()
    if (session) return

    const { error } = await client.auth.signInWithPassword({
      email: 'dev@aulendil.local',
      password: 'devpassword123',
    })
    if (error) {
      console.warn('[Aulendil] Dev auto-login failed — is Supabase running? Start with: supabase start')
    } else {
      console.log('[Aulendil] Auto-signed in as dev@aulendil.local')
    }
  }
})
PLUGINEOF

# Create Playwright config
mkdir -p tests/e2e
cat > playwright.config.ts << 'PWEOF'
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? "json" : "html",
  use: {
    baseURL: "http://localhost:3000",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: {
    command: "npm run dev -- --port 3000",
    port: 3000,
    reuseExistingServer: !process.env.CI,
    timeout: 60000,
  },
});
PWEOF
echo "  Created playwright.config.ts"

# Create starter e2e test: auth flow
cat > tests/e2e/auth.spec.ts << 'TESTEOF'
import { test, expect } from "@playwright/test";

test.describe("Authentication", () => {
  test("should load home page without errors", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (err) => errors.push(err.message));
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    expect(errors).toHaveLength(0);
  });

  test("should redirect unauthenticated users to login", async ({ page }) => {
    // Adapt this test to your app's protected routes
    // await page.goto("/dashboard");
    // await expect(page).toHaveURL(/login|auth|signin/);
  });

  test("should handle login flow", async ({ page }) => {
    // Adapt: fill in credentials and submit
    // await page.goto("/login");
    // await page.fill('[name="email"]', 'dev@aulendil.local');
    // await page.fill('[name="password"]', 'devpassword123');
    // await page.click('button[type="submit"]');
    // await expect(page).toHaveURL('/dashboard');
  });
});
TESTEOF
echo "  Created tests/e2e/auth.spec.ts"

# Create starter e2e test: smoke + accessibility
cat > tests/e2e/smoke.spec.ts << 'TESTEOF'
import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const pages = ["/"];

test.describe("Smoke Tests", () => {
  for (const path of pages) {
    test(`page loads without errors: ${path}`, async ({ page }) => {
      const errors: string[] = [];
      page.on("pageerror", (err) => errors.push(err.message));
      await page.goto(path);
      await page.waitForLoadState("networkidle");
      expect(errors).toHaveLength(0);
    });

    test(`accessibility check: ${path}`, async ({ page }) => {
      await page.goto(path);
      await page.waitForLoadState("networkidle");
      const results = await new AxeBuilder({ page }).analyze();
      expect(results.violations).toHaveLength(0);
    });
  }

  test("responsive: mobile viewport", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    const bodyWidth = await page.evaluate(() => document.body.scrollWidth);
    const viewportWidth = await page.evaluate(() => window.innerWidth);
    expect(bodyWidth).toBeLessThanOrEqual(viewportWidth + 5);
  });
});
TESTEOF
echo "  Created tests/e2e/smoke.spec.ts"

# Create starter e2e test: form patterns
cat > tests/e2e/forms.spec.ts << 'TESTEOF'
import { test, expect } from "@playwright/test";

test.describe("Form Patterns", () => {
  test("should validate required fields", async ({ page }) => {
    // Adapt: navigate to a page with a form
    await page.goto("/");
    // const submitButton = page.locator('button[type="submit"]');
    // if (await submitButton.isVisible()) {
    //   await submitButton.click();
    //   await expect(page.locator('.error, [role="alert"]')).toBeVisible();
    // }
  });

  test("should show success on valid submission", async ({ page }) => {
    // Adapt: fill form with valid data and submit
    await page.goto("/");
  });

  test("should show validation errors for invalid data", async ({ page }) => {
    // Adapt: fill form with invalid data
    await page.goto("/");
  });
});
TESTEOF
echo "  Created tests/e2e/forms.spec.ts"

# Create useRole composable for RBAC
cat > composables/useRole.ts << 'TSEOF'
import { ref, readonly } from "vue";

export function useRole() {
  const role = ref<string | null>(null);
  const loading = ref(false);
  const error = ref<string | null>(null);

  async function fetchRole() {
    const { useSupabaseClient } = await import("~/services/supabase");
    const client = useSupabaseClient();
    if (!client) {
      role.value = null;
      return;
    }

    loading.value = true;
    error.value = null;

    try {
      const { data: { user } } = await client.auth.getUser();
      if (!user) {
        role.value = null;
        return;
      }

      const { data, error: fetchError } = await client
        .from("user_roles")
        .select("roles(name)")
        .eq("user_id", user.id)
        .limit(1)
        .single();

      if (fetchError) {
        error.value = fetchError.message;
        role.value = null;
        return;
      }

      role.value = (data as any)?.roles?.name ?? null;
    } catch (e) {
      error.value = e instanceof Error ? e.message : "Failed to fetch role";
      role.value = null;
    } finally {
      loading.value = false;
    }
  }

  function hasRole(...roles: string[]): boolean {
    return role.value !== null && roles.includes(role.value);
  }

  function isAdmin(): boolean {
    return hasRole("admin");
  }

  function isManager(): boolean {
    return hasRole("admin", "manager");
  }

  return {
    role: readonly(role),
    loading: readonly(loading),
    error: readonly(error),
    fetchRole,
    hasRole,
    isAdmin,
    isManager,
  };
}
TSEOF
echo "  Created composables/useRole.ts"

# Update Supabase service to return null instead of throwing when not configured
cat > services/supabase.ts << 'TSEOF'
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let client: SupabaseClient | null = null;

export function isSupabaseConfigured(): boolean {
  const config = useRuntimeConfig();
  const url = config.public.supabaseUrl as string;
  const key = config.public.supabaseAnonKey as string;
  return Boolean(url && key);
}

export function useSupabaseClient(): SupabaseClient | null {
  if (client) return client;

  const config = useRuntimeConfig();
  const supabaseUrl = config.public.supabaseUrl as string;
  const supabaseAnonKey = config.public.supabaseAnonKey as string;

  if (!supabaseUrl || !supabaseAnonKey) {
    return null;
  }

  client = createClient(supabaseUrl, supabaseAnonKey);
  return client;
}
TSEOF

# Add test script to package.json
if command -v node &>/dev/null; then
    node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.scripts = pkg.scripts || {};
pkg.scripts.test = 'vitest run';
pkg.scripts['test:watch'] = 'vitest';
pkg.scripts.lint = 'eslint .';
pkg.scripts['type-check'] = 'nuxt prepare && vue-tsc --noEmit';
pkg.scripts['test:e2e'] = 'playwright test';
pkg.scripts['test:e2e:ui'] = 'playwright test --ui';
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
"
fi

cd ..
echo "  Frontend configured."
echo ""

# -- Backend configuration --

echo "  Setting up Python backend..."

# Create virtual environment
if [ ! -d "backend/.venv" ]; then
    $PYTHON_CMD -m venv backend/.venv
    echo "  Created virtual environment: backend/.venv"
fi

# Activate venv and install
if [[ "$OS_TYPE" == "windows" ]]; then
    VENV_ACTIVATE="backend/.venv/Scripts/activate"
else
    VENV_ACTIVATE="backend/.venv/bin/activate"
fi

if [ -f "$VENV_ACTIVATE" ]; then
    source "$VENV_ACTIVATE"
    echo "  Activated virtual environment"

    pip install -r backend/requirements.txt 2>&1 | tail -5
    pip install -r backend/requirements-dev.txt 2>&1 | tail -5
    INSTALLED+=("FastAPI, Uvicorn, Supabase client, dev tools")
else
    WARNINGS+=("Could not activate virtual environment")
fi

# Create base middleware files
cat > backend/middleware/__init__.py << 'PYEOF'
PYEOF

cat > backend/middleware/cors.py << 'PYEOF'
"""CORS middleware configuration — imported and applied in main.py."""
PYEOF

cat > backend/middleware/error_handler.py << 'PYEOF'
"""Global error handler middleware."""
import uuid
import logging
from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger(__name__)


class ErrorHandlerMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = str(uuid.uuid4())
        request.state.request_id = request_id
        try:
            response = await call_next(request)
            response.headers["X-Request-ID"] = request_id
            return response
        except Exception as exc:
            logger.exception(
                "Unhandled error",
                extra={"request_id": request_id, "path": str(request.url)},
            )
            return JSONResponse(
                status_code=500,
                content={
                    "status": "error",
                    "error": {
                        "code": "INTERNAL_ERROR",
                        "message": "An unexpected error occurred. Please try again.",
                    },
                    "meta": {"request_id": request_id},
                },
            )
PYEOF

cat > backend/middleware/auth.py << 'PYEOF'
"""Auth middleware — verifies Supabase JWT on protected routes."""
import os
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from supabase import create_client

security = HTTPBearer()

_supabase = None


def get_supabase():
    global _supabase
    if _supabase is None:
        url = os.getenv("SUPABASE_URL", "")
        key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
        _supabase = create_client(url, key)
    return _supabase


async def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security),
):
    """Verify JWT and return the authenticated user."""
    token = credentials.credentials
    sb = get_supabase()
    try:
        user_response = sb.auth.get_user(token)
        if not user_response or not user_response.user:
            raise HTTPException(status_code=401, detail="Invalid or expired token")
        request.state.user = user_response.user
        return user_response.user
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
PYEOF

# Create RBAC middleware
cat > backend/middleware/rbac.py << 'PYEOF'
"""RBAC middleware — role-based access control for FastAPI routes."""
from fastapi import Depends, HTTPException, status
from middleware.auth import get_current_user


async def get_current_user_role(user=Depends(get_current_user)):
    """Fetch the current user's role from user_roles table via Supabase."""
    import os
    from supabase import create_client

    url = os.getenv("SUPABASE_URL", "")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Auth service not configured",
        )

    sb = create_client(url, key)
    result = (
        sb.table("user_roles")
        .select("roles(name)")
        .eq("user_id", str(user.id))
        .limit(1)
        .maybe_single()
        .execute()
    )

    if not result.data:
        return None

    return result.data.get("roles", {}).get("name")


def require_role(*allowed_roles: str):
    """FastAPI dependency that checks if user has one of the allowed roles.

    Usage:
        @router.get("/admin", dependencies=[Depends(require_role("admin"))])
        async def admin_endpoint():
            ...
    """
    async def role_checker(role: str = Depends(get_current_user_role)):
        if role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions",
            )
        return role
    return role_checker
PYEOF
echo "  Created backend/middleware/rbac.py"

echo "  Backend configured."

cat > SETUP.md << 'SETUPEOF'
# Setup Guide

Run these steps in order the first time, or after a fresh clone.

## 1. Start Supabase (requires Docker)
supabase start

## 2. Run migrations
supabase db push

## 3. Seed app data (if supabase/seed-app.sql has content)
supabase db query < supabase/seed-app.sql

## 4. Start backend
cd backend && source .venv/bin/activate && uvicorn main:app --reload --port 8000

## 5. Start frontend
cd frontend && npm run dev

## Services
- Frontend: http://localhost:3000
- Backend API: http://localhost:8000
- API Docs: http://localhost:8000/docs
- Supabase Studio: http://127.0.0.1:54323

## Dev login
Email: dev@aulendil.local
Password: devpassword123
SETUPEOF
echo "  Created SETUP.md"
echo ""

# ============================================================
# Phase 3: Supabase
# ============================================================

echo "───────────────────────────────────────────────────────────"
echo " Phase 3: Supabase"
echo "───────────────────────────────────────────────────────────"
echo ""

# Install Supabase CLI if missing
if ! command -v supabase &>/dev/null; then
    echo "  Installing Supabase CLI..."
    if sys_install "supabase" "supabase/tap/supabase"; then
        INSTALLED+=("Supabase CLI")
    else
        WARNINGS+=("Cannot auto-install Supabase CLI. Install manually: https://supabase.com/docs/guides/cli")
    fi
fi

# Initialize Supabase if not already
if [ ! -f "supabase/config.toml" ]; then
    if command -v supabase &>/dev/null; then
        echo "  Initializing Supabase..."
        supabase init 2>&1 | tail -3 || true
        echo "  Supabase initialized."
    else
        WARNINGS+=("Supabase CLI not available — cannot initialize local Supabase")
    fi
else
    echo "  Supabase already initialized."
fi

# Start Supabase local (requires Docker)
SUPABASE_RUNNING=false
if command -v supabase &>/dev/null && command -v docker &>/dev/null; then
    echo "  Starting Supabase local (this may take a minute on first run)..."
    if supabase start 2>&1 | tail -10; then
        SUPABASE_RUNNING=true
        echo "  Supabase local is running."

        # Extract credentials from supabase status
        echo "  Extracting local Supabase credentials..."
        SUPA_STATUS=$(supabase status 2>/dev/null || true)

        CLEAN_STATUS=$(echo "$SUPA_STATUS" | tr -d '│╭╮╰╯├┤┬┴─')
        SUPA_URL=$(echo "$CLEAN_STATUS" | grep -E "API URL|Project URL" | awk '{print $NF}' | tr -d '[:space:]')
        SUPA_ANON=$(echo "$CLEAN_STATUS" | grep -E "anon key|Publishable" | awk '{print $NF}' | tr -d '[:space:]')
        SUPA_SERVICE=$(echo "$CLEAN_STATUS" | grep -E "service_role key|Secret" | head -1 | awk '{print $NF}' | tr -d '[:space:]')

        # Write .env.local
        cat > .env.local << ENVEOF
# Supabase local credentials (auto-generated by bootstrap.sh)
SUPABASE_URL=${SUPA_URL:-http://127.0.0.1:54321}
SUPABASE_ANON_KEY=${SUPA_ANON:-}
SUPABASE_SERVICE_ROLE_KEY=${SUPA_SERVICE:-}
API_BASE_URL=http://localhost:8000
APP_NAME=Aulendil
ENVEOF

        # Also create frontend .env (NUXT_PUBLIC_ prefix required for runtimeConfig.public)
        cat > frontend/.env << ENVEOF
# Supabase local credentials (auto-generated by bootstrap.sh)
NUXT_PUBLIC_SUPABASE_URL=${SUPA_URL:-http://127.0.0.1:54321}
NUXT_PUBLIC_SUPABASE_ANON_KEY=${SUPA_ANON:-}
NUXT_PUBLIC_API_BASE_URL=http://localhost:8000
ENVEOF

        echo "  Wrote .env.local and frontend/.env with local credentials."
        # Assign admin role to dev user after migrations
        if command -v supabase &>/dev/null; then
            echo "  Assigning admin role to dev user..."
            supabase db query "
              INSERT INTO user_roles (user_id, role_id)
              SELECT u.id, r.id
              FROM auth.users u, roles r
              WHERE u.email = 'dev@aulendil.local' AND r.name = 'admin'
              ON CONFLICT (user_id, role_id) DO NOTHING;
            " 2>/dev/null || echo "  (RBAC assignment deferred — apply migration first)"
        fi

        # Run app seed if it has content beyond the placeholder comment
        if [ -f "supabase/seed-app.sql" ] && grep -qv "^--" supabase/seed-app.sql 2>/dev/null; then
            echo "  Running app seed data..."
            supabase db query < supabase/seed-app.sql 2>/dev/null || true
        fi

        INSTALLED+=("Supabase local (running)")
    else
        WARNINGS+=("Failed to start Supabase local — check Docker is running")
    fi
else
    if ! command -v supabase &>/dev/null; then
        WARNINGS+=("Supabase CLI not installed — skipping local Supabase")
    elif ! command -v docker &>/dev/null; then
        WARNINGS+=("Docker not running — Supabase local requires Docker")
    fi

    # Write placeholder .env.local
    cat > .env.local << 'ENVEOF'
# Fill these in after starting Supabase local or connecting to a hosted project
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
API_BASE_URL=http://localhost:8000
APP_NAME=Aulendil
ENVEOF

    cat > frontend/.env << 'ENVEOF'
NUXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NUXT_PUBLIC_SUPABASE_ANON_KEY=
NUXT_PUBLIC_API_BASE_URL=http://localhost:8000
ENVEOF
fi

# Validate .env files don't contain instruction text instead of real values
for env_file in ".env.local" "frontend/.env"; do
    if [ -f "$env_file" ]; then
        if grep -qE '^[A-Z_]+=.{61,}' "$env_file" 2>/dev/null && \
           grep -E '^[A-Z_]+=.{61,}' "$env_file" | grep -qE '= *[A-Za-z].+ .+'; then
            echo "WARNING: $env_file may contain instructions instead of real values."
            echo "Open the file and make sure each line looks like KEY=value, not KEY=some explanation text."
            WARNINGS+=("$env_file may contain instructions instead of real values — check each KEY=value line")
        fi
    fi
done

echo ""

# ============================================================
# Phase 4: Start
# ============================================================

echo "───────────────────────────────────────────────────────────"
echo " Phase 4: Start"
echo "───────────────────────────────────────────────────────────"
echo ""

# Create logs directory
mkdir -p logs

# Start backend
echo "  Starting backend (FastAPI)..."
if [ -f "$VENV_ACTIVATE" ]; then
    source "$VENV_ACTIVATE"
fi
cd backend
uvicorn main:app --reload --port 8000 > ../logs/backend.log 2>&1 &
BACKEND_PID=$!
cd ..

# Start frontend
echo "  Starting frontend (Nuxt 3)..."
cd frontend
npm run dev -- --port 3000 > ../logs/frontend.log 2>&1 &
FRONTEND_PID=$!
cd ..

# Save PIDs for easy cleanup
cat > .pids << PIDEOF
BACKEND_PID=$BACKEND_PID
FRONTEND_PID=$FRONTEND_PID
PIDEOF

echo ""

# Wait for services (silently)
wait_for_url "http://localhost:8000/health" "Backend" || true
wait_for_url "http://localhost:3000" "Frontend" || true

echo ""

# ============================================================
# Phase 5: Dev Tools
# ============================================================

echo "───────────────────────────────────────────────────────────"
echo " Phase 5: Dev Tools"
echo "───────────────────────────────────────────────────────────"
echo ""

# gitleaks
if command -v gitleaks &>/dev/null; then
    echo "  gitleaks already installed"
    INSTALLED+=("gitleaks (secret scanning)")
else
    echo "  Installing gitleaks..."
    if sys_install "gitleaks" ""; then
        INSTALLED+=("gitleaks (secret scanning)")
    else
        WARNINGS+=("Cannot auto-install gitleaks. Install: https://github.com/gitleaks/gitleaks#installing")
    fi
fi

# k6
if command -v k6 &>/dev/null; then
    echo "  k6 already installed"
    INSTALLED+=("k6 (load testing)")
else
    echo "  Installing k6..."
    if sys_install "k6" ""; then
        INSTALLED+=("k6 (load testing)")
    else
        WARNINGS+=("Cannot auto-install k6. Install: https://k6.io/docs/get-started/installation/")
    fi
fi

# k6 load test scaffold
if [[ ! -f "frontend/tests/k6/load-test.js" ]]; then
    mkdir -p frontend/tests/k6
    cat > frontend/tests/k6/load-test.js << 'K6EOF'
import http from "k6/http";
import { check } from "k6";

export const options = {
  vus: 1,
  iterations: 10,
};

export default function () {
  const res = http.get("http://localhost:8000/health");
  check(res, {
    "status is 200": (r) => r.status === 200,
  });
}
K6EOF
    echo "  Created frontend/tests/k6/load-test.js"
fi

# Make all scripts executable
if [[ "$OS_TYPE" != "windows" ]]; then
    echo "  Setting executable permissions on scripts..."
    find .claude/hooks -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find .claude/scripts -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find scripts -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
fi

# Update .gitignore with additional entries
GITIGNORE_ENTRIES=(
    ".claude/audit.log"
    ".claude/tmp/"
    "CLAUDE.local.md"
    ".env.local"
    ".env"
    ".pids"
    "backend/.venv/"
    "logs/"
)

touch .gitignore
for entry in "${GITIGNORE_ENTRIES[@]}"; do
    if ! grep -qxF "$entry" .gitignore 2>/dev/null; then
        echo "$entry" >> .gitignore
    fi
done

echo ""

# ============================================================
# Summary
# ============================================================

echo "═══════════════════════════════════════════════════════════"
echo " BOOTSTRAP COMPLETE"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [[ ${#INSTALLED[@]} -gt 0 ]]; then
    echo "Installed/Configured:"
    for item in "${INSTALLED[@]}"; do
        echo "  + $item"
    done
    echo ""
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "Warnings:"
    for item in "${WARNINGS[@]}"; do
        echo "  ! $item"
    done
    echo ""
fi

echo "───────────────────────────────────────────────────────────"
echo ""
echo "  Your app is running at:"
echo ""
echo "    Frontend:  http://localhost:3000"
echo "    Backend:   http://localhost:8000"
echo "    API docs:  http://localhost:8000/docs"
if $SUPABASE_RUNNING; then
echo "    Supabase:  http://127.0.0.1:54323 (Studio)"
fi
echo ""
echo "  Server logs (servers run in the background):"
echo "    tail -f logs/backend.log"
echo "    tail -f logs/frontend.log"
echo ""
echo "  To stop the servers:"
echo "    bash scripts/stop.sh"
echo ""
echo "  Next steps:"
echo "    1. Edit CLAUDE.md — replace [APP_NAME] with your app name"
echo "    2. Open Claude Code and start describing what you want to build"
echo ""
echo "  You're in build mode — build freely, say 'ship it' when ready."
echo ""
