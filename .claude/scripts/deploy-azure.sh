#!/usr/bin/env bash
set -uo pipefail

# Deploy to Azure Container Apps
# Usage: bash .claude/scripts/deploy-azure.sh [staging|production]
# Requires: .env.azure, Docker, Azure CLI (az), logged in to ACR
# Exit 0 = deployed, Exit 1 = failed

ENVIRONMENT="${1:-staging}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
AUDIT_LOG=".claude/audit.log"
DEPLOY_STATE=".claude/deploy-state.json"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
echo "[$TIMESTAMP] deploy-azure: started env=$ENVIRONMENT" >> "$AUDIT_LOG"

echo "=========================================================="
echo " DEPLOY TO AZURE — $ENVIRONMENT"
echo " $TIMESTAMP"
echo "=========================================================="
echo ""

# Load Azure env vars
ENV_FILE="${ENV_FILE:-.env.azure}"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found. Run scaffold-azure-configs.sh first." >&2
    exit 1
fi
set -a; source "$ENV_FILE"; set +a

# Validate required vars
REQUIRED_VARS=(ACR_LOGIN_SERVER ACR_NAME AZURE_RESOURCE_GROUP AZURE_CONTAINER_APP_NAME APP_SCHEMA)
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: $var is not set in $ENV_FILE" >&2
        exit 1
    fi
done

APP_DASH="${AZURE_CONTAINER_APP_NAME}"
IMAGE_TAG="${ACR_LOGIN_SERVER}/${APP_DASH}:${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)"
IMAGE_LATEST="${ACR_LOGIN_SERVER}/${APP_DASH}:latest"

# ----------------------------------------------------------
# Step 1: Build Docker image
# ----------------------------------------------------------
echo "Building Docker image..."
if ! docker build -t "$IMAGE_TAG" -t "$IMAGE_LATEST" . 2>&1 | tee .claude/tmp/docker-build.log; then
    echo "ERROR: Docker build failed. See .claude/tmp/docker-build.log" >&2
    exit 1
fi
echo "  + Image built: $IMAGE_TAG"

# ----------------------------------------------------------
# Step 2: Push to Azure Container Registry
# ----------------------------------------------------------
echo ""
echo "Pushing to ACR..."
az acr login --name "$ACR_NAME" 2>&1 | tee -a .claude/tmp/docker-build.log
if ! docker push "$IMAGE_TAG" 2>&1 | tee -a .claude/tmp/docker-build.log; then
    echo "ERROR: Docker push failed." >&2
    exit 1
fi
docker push "$IMAGE_LATEST" 2>&1 | tee -a .claude/tmp/docker-build.log || true
echo "  + Pushed: $IMAGE_TAG"

# ----------------------------------------------------------
# Step 3: Update Container App revision
# ----------------------------------------------------------
echo ""
echo "Updating Container App revision..."
if ! az containerapp update \
    --name "$AZURE_CONTAINER_APP_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --image "$IMAGE_TAG" \
    --output table 2>&1; then
    echo "ERROR: Container App update failed." >&2
    exit 1
fi
echo "  + Container App updated"

# ----------------------------------------------------------
# Step 4: Wait for revision to be ready
# ----------------------------------------------------------
echo ""
echo "Waiting for revision to stabilise..."
sleep 15

# Get the app URL
DEPLOY_URL=$(az containerapp show \
    --name "$AZURE_CONTAINER_APP_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "properties.configuration.ingress.fqdn" \
    --output tsv 2>/dev/null || echo "")

if [[ -n "$DEPLOY_URL" ]]; then
    DEPLOY_URL="https://$DEPLOY_URL"
    echo "  + App URL: $DEPLOY_URL"
fi

# ----------------------------------------------------------
# Step 5: Smoke test
# ----------------------------------------------------------
echo ""
echo "Running smoke test..."
SMOKE_OK=false
if [[ -n "$DEPLOY_URL" ]]; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 "$DEPLOY_URL" 2>/dev/null || echo "000")
    if [[ "$HTTP_STATUS" =~ ^(200|301|302|401)$ ]]; then
        echo "  + Smoke test passed (HTTP $HTTP_STATUS)"
        SMOKE_OK=true
    else
        echo "  WARNING: Smoke test returned HTTP $HTTP_STATUS"
    fi
fi

# ----------------------------------------------------------
# Step 6: Update deploy-state.json
# ----------------------------------------------------------
DEPLOY_STATUS="success"
[[ "$SMOKE_OK" == "false" ]] && DEPLOY_STATUS="deployed-smoke-warn"

if command -v jq &>/dev/null && [[ -f "$DEPLOY_STATE" ]]; then
    UPDATED=$(jq --arg url "$DEPLOY_URL" \
        --arg img "$IMAGE_TAG" \
        --arg schema "$APP_SCHEMA" \
        --arg ts "$TIMESTAMP" \
        --arg status "$DEPLOY_STATUS" \
        '.azure.provider = "azure" |
         .azure.app_schema = $schema |
         .azure.deploy_url = $url |
         .azure.acr_image = $img |
         .azure.last_deploy_at = $ts |
         .azure.last_deploy_status = $status' \
        "$DEPLOY_STATE" 2>/dev/null)
    if [[ -n "$UPDATED" ]]; then
        echo "$UPDATED" > "$DEPLOY_STATE"
    fi
fi

echo ""
echo "=========================================================="
echo " DEPLOYED — $ENVIRONMENT"
[[ -n "$DEPLOY_URL" ]] && echo " URL: $DEPLOY_URL"
echo "=========================================================="
echo "[$TIMESTAMP] deploy-azure: completed status=$DEPLOY_STATUS" >> "$AUDIT_LOG"
exit 0
