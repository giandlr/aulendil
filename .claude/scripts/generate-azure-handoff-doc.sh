#!/usr/bin/env bash
set -uo pipefail

# Generate IT setup guide for Azure deployment
# Usage: bash .claude/scripts/generate-azure-handoff-doc.sh
# Output: docs/azure-it-setup-guide.md
# Exit 0 = success

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
AUDIT_LOG=".claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
mkdir -p docs 2>/dev/null || true
echo "[$TIMESTAMP] generate-azure-handoff-doc: started" >> "$AUDIT_LOG"

APP_NAME="${APP_NAME:-$(basename "$(pwd)" | tr '-' '_' | tr '[:upper:]' '[:lower:]')}"
APP_SCHEMA="${APP_SCHEMA:-$APP_NAME}"
APP_DASH="${APP_NAME//_/-}"
OUTPUT="docs/azure-it-setup-guide.md"

cat > "$OUTPUT" << MDEOF
# Azure IT Setup Guide — ${APP_NAME}

Generated: ${TIMESTAMP}

This guide walks your IT team through the one-time Azure infrastructure setup for deploying **${APP_NAME}**.
After setup, developers run \`bash .claude/scripts/deploy-azure.sh\` for each release.

---

## Prerequisites

- Azure subscription with Contributor access
- Azure CLI installed and authenticated (\`az login\`)
- Docker installed locally
- Google Workspace admin access (for OAuth app registration)

---

## Estimated Costs (approximate — verify at [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/))

| Resource | Estimated Cost |
|---|---|
| Azure Container Apps (0.5 vCPU, 1 GB) | ~\$15–30/month per app |
| Azure Database for PostgreSQL Flexible | Shared with other apps (one server) |
| Azure Blob Storage | ~\$1–5/month per app |
| Azure Container Registry (Basic) | ~\$5/month (shared) |

---

## Step 1 — Resource Group

\`\`\`bash
az group create --name rg-apps --location eastus
\`\`\`

---

## Step 2 — Azure Container Registry (shared, once per organisation)

\`\`\`bash
az acr create --resource-group rg-apps --name <your-acr-name> --sku Basic
az acr login --name <your-acr-name>
\`\`\`

---

## Step 3 — Azure Container Apps Environment (shared, once per organisation)

\`\`\`bash
az containerapp env create \\
  --name cae-apps \\
  --resource-group rg-apps \\
  --location eastus
\`\`\`

---

## Step 4 — PostgreSQL Flexible Server (shared, once per organisation)

\`\`\`bash
az postgres flexible-server create \\
  --resource-group rg-apps \\
  --name psql-apps \\
  --admin-user pgadmin \\
  --admin-password "<secure-password>" \\
  --sku-name Standard_B2s \\
  --tier Burstable \\
  --version 15 \\
  --public-access 0.0.0.0
\`\`\`

### Per-App Schema Setup

For each new app, run:

\`\`\`bash
ADMIN_DATABASE_URL="postgresql://pgadmin:<password>@psql-apps.postgres.database.azure.com:5432/postgres" \\
  bash .claude/scripts/setup-azure-db.sh ${APP_SCHEMA}
\`\`\`

This creates schema \`${APP_SCHEMA}\` and role \`${APP_SCHEMA}_owner\` with a unique password.
The script outputs the \`DATABASE_URL\` — save it for Step 7.

---

## Step 5 — Azure Blob Storage (shared per organisation, per-app container)

\`\`\`bash
az storage account create \\
  --resource-group rg-apps \\
  --name strapps \\
  --sku Standard_LRS \\
  --kind StorageV2

az storage container create \\
  --account-name strapps \\
  --name ${APP_SCHEMA} \\
  --auth-mode login
\`\`\`

Get the connection string:
\`\`\`bash
az storage account show-connection-string --name strapps --resource-group rg-apps
\`\`\`

---

## Step 6 — Google OAuth Client (for employee SSO)

1. Go to [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → Credentials
2. Create OAuth 2.0 Client ID (Web application)
3. Add Authorised redirect URI: \`https://<app-fqdn>/oauth2/callback\`
4. Note the Client ID and Client Secret

**Email domain restriction:** OAuth2 Proxy will restrict login to your company domain.
Set \`AZURE_ALLOWED_EMAIL_DOMAIN=yourcompany.com\` in \`.env.azure\`.

---

## Step 7 — Fill .env.azure

Copy \`.env.azure.template\` to \`.env.azure\` and fill in:

| Variable | Where to Get It |
|---|---|
| \`DATABASE_URL\` | Output of setup-azure-db.sh (Step 4) |
| \`AZURE_STORAGE_CONNECTION_STRING\` | Output of Step 5 |
| \`GOOGLE_CLIENT_ID\` | Google Cloud Console (Step 6) |
| \`GOOGLE_CLIENT_SECRET\` | Google Cloud Console (Step 6) |
| \`OAUTH2_PROXY_COOKIE_SECRET\` | \`openssl rand -base64 32\` |
| \`AZURE_ALLOWED_EMAIL_DOMAIN\` | Your company email domain |
| \`ACR_NAME\` | Container Registry name from Step 2 |
| \`ACR_LOGIN_SERVER\` | \`<acr-name>.azurecr.io\` |
| \`AZURE_RESOURCE_GROUP\` | \`rg-apps\` |
| \`AZURE_CONTAINER_APP_ENV\` | \`cae-apps\` |

---

## Step 8 — First Deploy

\`\`\`bash
bash .claude/scripts/scaffold-azure-configs.sh
bash .claude/scripts/deploy-azure.sh staging
\`\`\`

---

## Step 9 — Network & DNS (optional)

- Add a custom domain in Azure Container Apps → Custom domains
- Point DNS CNAME to the Container App FQDN
- TLS certificate is provisioned automatically

---

## Step 10 — Monitoring Alerts

\`\`\`bash
# CPU alert (>80% for 5 minutes)
az monitor metrics alert create \\
  --name "${APP_DASH}-cpu-alert" \\
  --resource-group rg-apps \\
  --scopes <container-app-resource-id> \\
  --condition "avg Percentage CPU > 80" \\
  --window-size 5m \\
  --evaluation-frequency 1m \\
  --action <action-group-id>
\`\`\`

---

## VNet Integration (optional — for private database access)

\`\`\`bash
az containerapp env update \\
  --name cae-apps \\
  --resource-group rg-apps \\
  --infrastructure-subnet-resource-id <subnet-id>
\`\`\`

---

*Generated by Aulendil — Azure handoff doc generator*
MDEOF

echo "IT setup guide written to: $OUTPUT"
echo "[$TIMESTAMP] generate-azure-handoff-doc: completed output=$OUTPUT" >> "$AUDIT_LOG"
exit 0
