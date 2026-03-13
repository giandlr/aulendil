#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Sprout Bootstrap — From empty directory to running app
#
# Usage: bash scripts/sprout-bootstrap.sh
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
echo " SPROUT BOOTSTRAP"
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
# Phase 1: Scaffold
# ============================================================

echo "───────────────────────────────────────────────────────────"
echo " Phase 1: Scaffold"
echo "───────────────────────────────────────────────────────────"
echo ""

# Frontend — Nuxt 3
if [ ! -d "frontend" ]; then
    echo "  Creating Nuxt 3 frontend..."
    npx -y nuxi@latest init frontend --template v3 --no-install 2>&1 | tail -5
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
    title=os.getenv("APP_NAME", "Sprout App"),
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

    echo "  Created backend/ with main.py, requirements, and directory structure"
else
    echo "  backend/ already exists — skipping scaffold"
fi

# Supabase directory
echo "  Creating Supabase directories..."
mkdir -p supabase/migrations
mkdir -p supabase/functions
echo "  Created supabase/migrations and supabase/functions"

# Create seed.sql with dev user for local development
if [ ! -f "supabase/seed.sql" ]; then
    cat > supabase/seed.sql << 'SEEDEOF'
-- Dev user for local development: dev@sprout.local / devpassword123
INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new,
    email_change_token_current, phone, phone_change, phone_change_token,
    reauthentication_token, is_sso_user, is_anonymous
) VALUES (
    'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'dev@sprout.local',
    crypt('devpassword123', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"Dev User"}'::jsonb,
    now(), now(), '', '', '', '', '', '', '', '', '', false, false
) ON CONFLICT (id) DO NOTHING;
INSERT INTO auth.identities (
    id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at
) VALUES (
    'a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001',
    'dev@sprout.local', 'email',
    '{"sub":"a0000000-0000-0000-0000-000000000001","email":"dev@sprout.local"}'::jsonb,
    now(), now(), now()
) ON CONFLICT (provider_id, provider) DO NOTHING;
SEEDEOF
    echo "  Created supabase/seed.sql with dev user (dev@sprout.local / devpassword123)"
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
npm install @vee-validate/nuxt @vee-validate/zod vee-validate zod 2>&1 | tail -3
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

# Create/update nuxt.config.ts
cat > nuxt.config.ts << 'NUXTEOF'
import tailwindcss from "@tailwindcss/vite";

export default defineNuxtConfig({
  compatibilityDate: "2024-11-01",
  devtools: { enabled: true },

  modules: [
    "@pinia/nuxt",
  ],

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
          Sprout App
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

  if (!config.public.supabaseUrl) missing.push('SUPABASE_URL')
  if (!config.public.supabaseAnonKey) missing.push('SUPABASE_ANON_KEY')

  const envMissing = useState<string[]>('envMissing', () => missing)

  if (missing.length > 0) {
    envMissing.value = missing
    console.warn(`[Sprout] Missing environment variables: ${missing.join(', ')}. The app will work without a database — data will appear once you connect Supabase.`)
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
      email: 'dev@sprout.local',
      password: 'devpassword123',
    })
    if (!error) {
      console.log('[Sprout] Auto-signed in as dev@sprout.local')
    }
  }
})
PLUGINEOF

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
pkg.scripts['type-check'] = 'vue-tsc --noEmit';
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

echo "  Backend configured."
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
# Supabase local credentials (auto-generated by sprout-bootstrap.sh)
SUPABASE_URL=${SUPA_URL:-http://127.0.0.1:54321}
SUPABASE_ANON_KEY=${SUPA_ANON:-}
SUPABASE_SERVICE_ROLE_KEY=${SUPA_SERVICE:-}
API_BASE_URL=http://localhost:8000
APP_NAME=Sprout App
ENVEOF

        # Also create frontend .env
        cat > frontend/.env << ENVEOF
# Supabase local credentials (auto-generated by sprout-bootstrap.sh)
SUPABASE_URL=${SUPA_URL:-http://127.0.0.1:54321}
SUPABASE_ANON_KEY=${SUPA_ANON:-}
API_BASE_URL=http://localhost:8000
ENVEOF

        echo "  Wrote .env.local and frontend/.env with local credentials."
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
APP_NAME=Sprout App
ENVEOF

    cat > frontend/.env << 'ENVEOF'
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=
API_BASE_URL=http://localhost:8000
ENVEOF
fi

echo ""

# ============================================================
# Phase 4: Start
# ============================================================

echo "───────────────────────────────────────────────────────────"
echo " Phase 4: Start"
echo "───────────────────────────────────────────────────────────"
echo ""

# Start backend
echo "  Starting backend (FastAPI)..."
if [ -f "$VENV_ACTIVATE" ]; then
    source "$VENV_ACTIVATE"
fi
cd backend
uvicorn main:app --reload --port 8000 &
BACKEND_PID=$!
cd ..
echo "  Backend starting on http://localhost:8000 (PID: $BACKEND_PID)"

# Start frontend
echo "  Starting frontend (Nuxt 3)..."
cd frontend
npm run dev -- --port 3000 &
FRONTEND_PID=$!
cd ..
echo "  Frontend starting on http://localhost:3000 (PID: $FRONTEND_PID)"

echo ""

# Wait for services
echo "  Waiting for services to be ready..."
wait_for_url "http://localhost:8000/health" "Backend" || true
wait_for_url "http://localhost:3000" "Frontend" || true

# Save PIDs for easy cleanup
cat > .sprout-pids << PIDEOF
BACKEND_PID=$BACKEND_PID
FRONTEND_PID=$FRONTEND_PID
PIDEOF

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
    ".sprout-pids"
    "backend/.venv/"
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
echo "  To stop the servers:"
echo "    kill \$(cat .sprout-pids | grep PID | cut -d= -f2)"
echo ""
echo "  Next steps:"
echo "    1. Edit CLAUDE.md — replace [APP_NAME] with your app name"
echo "    2. Open Claude Code and start describing what you want to build"
echo ""
echo "  You're in build mode — build freely, say 'ship it' when ready."
echo ""
