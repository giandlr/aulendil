#!/usr/bin/env bash
set -uo pipefail

# Cross-platform Python detection
_find_python() {
    for _py in python3 python py; do
        if command -v "$_py" &>/dev/null; then
            echo "$_py"
            return 0
        fi
    done
    echo ""
}
PYTHON_CMD=$(_find_python)
if [[ -z "$PYTHON_CMD" ]]; then
    echo "ERROR: Python not found. Install Python 3 from https://python.org" >&2
    exit 1
fi

# Scaffold Azure deployment configs into the current project
# Usage: bash .claude/scripts/scaffold-azure-configs.sh
# Generates: Dockerfile, docker-compose.azure.yml, .env.azure.template,
#            azure-container-app.yml, backend/auth.py, frontend/composables/useAuth.ts
# Exit 0 = success, Exit 1 = error

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
AUDIT_LOG=".claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
echo "[$TIMESTAMP] scaffold-azure-configs: started" >> "$AUDIT_LOG"

echo "=========================================================="
echo " SCAFFOLD AZURE CONFIGS"
echo "=========================================================="
echo ""

APP_NAME="${APP_NAME:-$(basename "$(pwd)" | tr '-' '_' | tr '[:upper:]' '[:lower:]')}"
APP_SCHEMA="${APP_SCHEMA:-$APP_NAME}"
BLOB_CONTAINER="${BLOB_CONTAINER:-$APP_NAME}"
APP_DASH="${APP_NAME//_/-}"

echo "  App name:       $APP_NAME"
echo "  App schema:     $APP_SCHEMA"
echo "  Blob container: $BLOB_CONTAINER"
echo ""

# ----------------------------------------------------------
# 1. Dockerfile
# ----------------------------------------------------------
if [[ ! -f "Dockerfile" ]]; then
    cat > Dockerfile << 'EOF'
# syntax=docker/dockerfile:1
# Multi-stage build: frontend build then production image

FROM node:20-alpine AS frontend-build
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm ci --prefer-offline
COPY frontend/ ./
RUN npm run build

FROM python:3.11-slim AS production
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
COPY backend/requirements.txt ./backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt
COPY backend/ ./backend/
COPY --from=frontend-build /app/frontend/.output ./frontend/.output
COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh
EXPOSE 3000 8000
ENTRYPOINT ["./docker-entrypoint.sh"]
EOF
    echo "  + Created Dockerfile"
else
    echo "  - Dockerfile already exists, skipping"
fi

# ----------------------------------------------------------
# 2. docker-entrypoint.sh
# ----------------------------------------------------------
if [[ ! -f "docker-entrypoint.sh" ]]; then
    printf '#!/bin/sh\nset -e\nuvicorn backend.main:app --host 0.0.0.0 --port 8000 &\nnode frontend/.output/server/index.mjs\n' \
        > docker-entrypoint.sh
    chmod +x docker-entrypoint.sh
    echo "  + Created docker-entrypoint.sh"
fi

# ----------------------------------------------------------
# 3. docker-compose.azure.yml
# ----------------------------------------------------------
if [[ ! -f "docker-compose.azure.yml" ]]; then
    cat > docker-compose.azure.yml << EOF
version: "3.9"
services:
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:latest
    ports: ["4180:4180"]
    environment:
      OAUTH2_PROXY_PROVIDER: google
      OAUTH2_PROXY_CLIENT_ID: \${GOOGLE_CLIENT_ID}
      OAUTH2_PROXY_CLIENT_SECRET: \${GOOGLE_CLIENT_SECRET}
      OAUTH2_PROXY_COOKIE_SECRET: \${OAUTH2_PROXY_COOKIE_SECRET}
      OAUTH2_PROXY_EMAIL_DOMAIN: \${AZURE_ALLOWED_EMAIL_DOMAIN}
      OAUTH2_PROXY_UPSTREAM: http://app:3000
      OAUTH2_PROXY_HTTP_ADDRESS: 0.0.0.0:4180
      OAUTH2_PROXY_PASS_USER_HEADERS: "true"
    depends_on: [app]
  app:
    build: .
    ports: ["3000:3000", "8000:8000"]
    environment:
      DEPLOY_TARGET: azure
      APP_SCHEMA: ${APP_SCHEMA}
      BLOB_CONTAINER: ${BLOB_CONTAINER}
      DATABASE_URL: \${DATABASE_URL}
      AZURE_STORAGE_CONNECTION_STRING: \${AZURE_STORAGE_CONNECTION_STRING}
    env_file: [.env.azure]
EOF
    echo "  + Created docker-compose.azure.yml"
fi

# ----------------------------------------------------------
# 4. .env.azure.template
# ----------------------------------------------------------
if [[ ! -f ".env.azure.template" ]]; then
    cat > .env.azure.template << EOF
# Azure deployment environment variables
# Copy to .env.azure and fill in values — never commit .env.azure

DEPLOY_TARGET=azure
APP_SCHEMA=${APP_SCHEMA}
BLOB_CONTAINER=${BLOB_CONTAINER}

# Database connection (output of setup-azure-db.sh)
DATABASE_URL=postgresql://${APP_SCHEMA}_owner:CHANGE_ME@DB_HOST:5432/DB_NAME

# Azure Blob Storage
AZURE_STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=https;AccountName=CHANGE_ME;AccountKey=CHANGE_ME;EndpointSuffix=core.windows.net

# Google OAuth (for OAuth2 Proxy)
GOOGLE_CLIENT_ID=CHANGE_ME
GOOGLE_CLIENT_SECRET=CHANGE_ME
OAUTH2_PROXY_COOKIE_SECRET=CHANGE_ME_32_BYTE_BASE64

# Restrict login to this company email domain
AZURE_ALLOWED_EMAIL_DOMAIN=CHANGE_ME

# Azure Container Registry
ACR_NAME=CHANGE_ME
ACR_LOGIN_SERVER=CHANGE_ME.azurecr.io

# Azure Container Apps
AZURE_RESOURCE_GROUP=CHANGE_ME
AZURE_CONTAINER_APP_NAME=${APP_DASH}-app
AZURE_CONTAINER_APP_ENV=CHANGE_ME
EOF
    echo "  + Created .env.azure.template"
fi

# ----------------------------------------------------------
# 5. azure-container-app.yml
# ----------------------------------------------------------
if [[ ! -f "azure-container-app.yml" ]]; then
    cat > azure-container-app.yml << EOF
# Apply: az containerapp create --yaml azure-container-app.yml
properties:
  configuration:
    ingress:
      external: true
      targetPort: 3000
      transport: http
    registries:
      - server: \${ACR_LOGIN_SERVER}
  template:
    containers:
      - name: app
        image: \${ACR_LOGIN_SERVER}/${APP_DASH}:latest
        resources:
          cpu: 0.5
          memory: 1Gi
        env:
          - name: DEPLOY_TARGET
            value: azure
          - name: APP_SCHEMA
            value: ${APP_SCHEMA}
          - name: BLOB_CONTAINER
            value: ${BLOB_CONTAINER}
          - name: DATABASE_URL
            secretRef: database-url
          - name: AZURE_STORAGE_CONNECTION_STRING
            secretRef: azure-storage-connection
EOF
    echo "  + Created azure-container-app.yml"
fi

# ----------------------------------------------------------
# 6. backend/auth.py (dual-mode identity abstraction)
#    See .claude/rules/auth.md — Azure Auth section for full spec
# ----------------------------------------------------------
if [[ -d "backend" && ! -f "backend/auth.py" ]]; then
    "$PYTHON_CMD" - << 'PYEOF'
import textwrap, pathlib
content = textwrap.dedent('''
    """
    Dual-mode authentication — see .claude/rules/auth.md for full spec.
    DEPLOY_TARGET=azure:  reads X-Forwarded-Email from OAuth2 Proxy
    DEPLOY_TARGET=vercel: reads Supabase Auth JWT
    """
    import os
    from typing import Optional
    from fastapi import HTTPException, Request
    from pydantic import BaseModel


    class CurrentUser(BaseModel):
        id: Optional[str] = None
        email: str
        source: str  # "supabase" or "azure-proxy"


    async def get_or_create_user_by_email(email: str, db) -> CurrentUser:
        """Upsert user record keyed by email (first-login pattern for Azure)."""
        res = db.table("users").upsert({"email": email}, on_conflict="email").execute()
        row = res.data[0] if res.data else {"email": email}
        return CurrentUser(id=row.get("id"), email=row["email"], source="azure-proxy")


    async def get_current_user(request: Request, db=None) -> CurrentUser:
        """Returns the current user based on DEPLOY_TARGET env var."""
        target = os.getenv("DEPLOY_TARGET", "vercel")
        if target == "azure":
            email = request.headers.get("X-Forwarded-Email")
            if not email:
                raise HTTPException(status_code=401, detail="Unauthorized")
            return await get_or_create_user_by_email(email, db)

        auth_header = request.headers.get("Authorization", "")
        token = auth_header.removeprefix("Bearer ").strip()
        if not token:
            raise HTTPException(status_code=401, detail="Unauthorized")
        try:
            from supabase import create_client  # type: ignore
            client = create_client(
                os.environ["SUPABASE_URL"],
                os.environ["SUPABASE_SERVICE_ROLE_KEY"],
            )
            resp = client.auth.get_user(token)
            if not resp.user:
                raise HTTPException(status_code=401, detail="Unauthorized")
            return CurrentUser(
                id=str(resp.user.id), email=resp.user.email or "", source="supabase"
            )
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(status_code=401, detail="Unauthorized")
''').lstrip()
pathlib.Path("backend/auth.py").write_text(content)
print("  + Created backend/auth.py")
PYEOF
elif [[ ! -d "backend" ]]; then
    echo "  - backend/ not found — auth.py will be created on bootstrap"
fi

# ----------------------------------------------------------
# 7. frontend/composables/useAuth.ts
#    See .claude/rules/auth.md — Azure Auth section for full spec
# ----------------------------------------------------------
if [[ -d "frontend/composables" && ! -f "frontend/composables/useAuth.ts" ]]; then
    "$PYTHON_CMD" - << 'PYEOF'
import textwrap, pathlib
content = textwrap.dedent('''
    /**
     * Dual-mode auth composable — see .claude/rules/auth.md for full spec.
     * DEPLOY_TARGET=azure:  session via OAuth2 Proxy cookie, reads /api/me
     * DEPLOY_TARGET=vercel: Supabase Auth client
     */
    import { ref, readonly } from "vue"

    interface AuthUser {
      id?: string
      email: string
      source: "supabase" | "azure-proxy"
    }

    const user = ref<AuthUser | null>(null)
    const isLoading = ref(false)
    const error = ref<string | null>(null)

    export function useAuth() {
      const config = useRuntimeConfig()
      const deployTarget = config.public.deployTarget ?? "vercel"

      async function fetchCurrentUser() {
        isLoading.value = true
        error.value = null
        try {
          if (deployTarget === "azure") {
            const data = await $fetch<AuthUser>("/api/me")
            user.value = data
          } else {
            const { $supabase } = useNuxtApp() as any
            const { data: { user: sbUser } } = await $supabase.auth.getUser()
            if (sbUser) {
              user.value = { id: sbUser.id, email: sbUser.email ?? "", source: "supabase" }
            }
          }
        } catch (e: any) {
          error.value = e?.message ?? "Could not load user"
        } finally {
          isLoading.value = false
        }
      }

      async function signOut() {
        if (deployTarget === "azure") {
          window.location.href = "/oauth2/sign_out"
        } else {
          const { $supabase } = useNuxtApp() as any
          await $supabase.auth.signOut()
          user.value = null
          await navigateTo("/login")
        }
      }

      return { user: readonly(user), isLoading: readonly(isLoading), error: readonly(error), fetchCurrentUser, signOut }
    }
''').lstrip()
pathlib.Path("frontend/composables/useAuth.ts").write_text(content)
print("  + Created frontend/composables/useAuth.ts")
PYEOF
elif [[ ! -d "frontend/composables" ]]; then
    echo "  - frontend/composables/ not found — useAuth.ts will be created on bootstrap"
fi

# ----------------------------------------------------------
# 8. Set DEPLOY_TARGET=azure in .env if present
# ----------------------------------------------------------
ENV_FILE="${ENV_FILE:-.env}"
if [[ -f "$ENV_FILE" ]]; then
    if grep -q "^DEPLOY_TARGET=" "$ENV_FILE" 2>/dev/null; then
        sed -i.bak 's|^DEPLOY_TARGET=.*|DEPLOY_TARGET=azure|' "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
    else
        printf '\nDEPLOY_TARGET=azure\nAPP_SCHEMA=%s\nBLOB_CONTAINER=%s\n' "$APP_SCHEMA" "$BLOB_CONTAINER" >> "$ENV_FILE"
    fi
    echo "  + Updated DEPLOY_TARGET=azure in $ENV_FILE"
fi

echo ""
echo "Azure configs scaffolded:"
echo "  Dockerfile                          multistage Docker build"
echo "  docker-compose.azure.yml            local Azure topology test"
echo "  .env.azure.template                 fill in secrets, copy to .env.azure"
echo "  azure-container-app.yml             Container Apps deployment definition"
[[ -f "backend/auth.py" ]]                  && echo "  backend/auth.py                     dual-mode auth abstraction"
[[ -f "frontend/composables/useAuth.ts" ]]  && echo "  frontend/composables/useAuth.ts     dual-mode auth composable"
echo ""
echo "Next: fill .env.azure.template, then run:"
echo "  bash .claude/scripts/setup-azure-db.sh \$APP_SCHEMA"
echo "  bash .claude/scripts/deploy-azure.sh staging"

# ----------------------------------------------------------
# 9. When BACKEND_LANGUAGE=csharp, swap Dockerfile for the .NET 8 variant.
#    The dotnet runtime image is used; no Python layer needed.
# ----------------------------------------------------------
BACKEND_LANGUAGE="${BACKEND_LANGUAGE:-python}"
if [[ -f ".env" ]]; then
    _bl=$(grep -E "^BACKEND_LANGUAGE=" .env 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"' | tr -d "'")
    [[ -n "$_bl" ]] && BACKEND_LANGUAGE="$_bl"
fi

if [[ "$BACKEND_LANGUAGE" == "csharp" ]] && [[ -f "Dockerfile" ]]; then
    if grep -q "python:3.11-slim" Dockerfile 2>/dev/null; then
        echo "  Rewriting Dockerfile for .NET 8 runtime..."
        # Write to temp file first, then move into place
        DOTNET_DOCKERFILE="Dockerfile.net8.tmp"
        {
            echo '# syntax=docker/dockerfile:1'
            echo '# Multi-stage: Nuxt frontend build + dotnet publish + aspnet runtime'
            echo ''
            echo 'FROM node:20-alpine AS frontend-build'
            echo 'WORKDIR /app/frontend'
            echo 'COPY frontend/package*.json ./'
            echo 'RUN npm ci --prefer-offline'
            echo 'COPY frontend/ ./'
            echo 'RUN npm run build'
            echo ''
            echo 'FROM mcr.microsoft.com/dotnet/sdk:8.0 AS backend-build'
            echo 'WORKDIR /app/backend'
            echo 'COPY backend/backend.csproj ./'
            echo 'RUN dotnet restore'
            echo 'COPY backend/ ./'
            echo 'RUN dotnet publish -c Release -o /app/publish'
            echo ''
            echo 'FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS production'
            echo 'WORKDIR /app'
            echo 'RUN apt-get -q -y install curl && rm -rf /var/lib/apt/lists/*'
            echo 'COPY --from=backend-build /app/publish ./backend/'
            echo 'COPY --from=frontend-build /app/frontend/.output ./frontend/.output'
            echo 'COPY docker-entrypoint.sh ./'
            echo 'RUN chmod +x docker-entrypoint.sh'
            echo 'EXPOSE 3000 8000'
            echo 'ENTRYPOINT ["./docker-entrypoint.sh"]'
        } > "$DOTNET_DOCKERFILE"
        mv Dockerfile Dockerfile.python.bak
        mv "$DOTNET_DOCKERFILE" Dockerfile
        echo "  Dockerfile rewritten for .NET 8 (Python backup at Dockerfile.python.bak)"
    fi
fi

echo "[$TIMESTAMP] scaffold-azure-configs: completed" >> "$AUDIT_LOG"
exit 0
