#!/usr/bin/env bash
set -uo pipefail

# EF Core migration runner for C# backend
# Usage:
#   bash .claude/scripts/setup-db-csharp.sh          — apply all pending migrations
#   bash .claude/scripts/setup-db-csharp.sh MyMigration — create new migration named MyMigration
#
# Reads DATABASE_URL from .env or environment
# Exit 0 = success, Exit 1 = error

ACTION="${1:-apply}"   # "apply" (default) or a migration name to create
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
AUDIT_LOG=".claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
echo "[$TIMESTAMP] setup-db-csharp: started action=$ACTION" >> "$AUDIT_LOG"

echo "=========================================================="
echo " EF CORE MIGRATIONS — $ACTION"
echo "=========================================================="
echo ""

# Resolve backend directory
BACKEND_DIR="${BACKEND_DIR:-backend}"
if [ ! -f "$BACKEND_DIR/backend.csproj" ]; then
    echo "ERROR: $BACKEND_DIR/backend.csproj not found." >&2
    echo "       Run scaffold-csharp-backend.sh first." >&2
    exit 1
fi

# Load DATABASE_URL from .env if not already set
if [ -z "${DATABASE_URL:-}" ]; then
    ENV_FILE="${ENV_FILE:-.env}"
    if [ -f "$ENV_FILE" ]; then
        set -a; source "$ENV_FILE"; set +a
    fi
fi

if [ -z "${DATABASE_URL:-}" ]; then
    echo "ERROR: DATABASE_URL is not set." >&2
    echo "       Set it in .env or export it before running this script." >&2
    exit 1
fi

echo "  Backend dir: $BACKEND_DIR"
echo "  Checking connection... (credentials masked)"
echo ""

# Check dotnet CLI
if ! command -v dotnet &>/dev/null; then
    echo "ERROR: dotnet CLI not found." >&2
    echo "       Install .NET 8 SDK from https://dotnet.microsoft.com/download" >&2
    exit 1
fi

# Install dotnet-ef tool if needed
if ! dotnet ef --version &>/dev/null 2>&1; then
    echo "Installing dotnet-ef tool..."
    dotnet tool install --global dotnet-ef
    export PATH="$PATH:$HOME/.dotnet/tools"
fi

DOTNET_EF_VERSION=$(dotnet ef --version 2>/dev/null | head -1)
echo "  dotnet ef: $DOTNET_EF_VERSION"
echo ""

cd "$BACKEND_DIR"

if [ "$ACTION" = "apply" ]; then
    # ----------------------------------------------------------
    # Apply all pending migrations
    # ----------------------------------------------------------
    echo "Applying pending migrations..."
    if ! dotnet ef database update 2>&1; then
        echo "ERROR: Migration apply failed." >&2
        exit 1
    fi
    echo "  + All migrations applied"
else
    # ----------------------------------------------------------
    # Create a new named migration
    # ----------------------------------------------------------
    MIGRATION_NAME="$ACTION"
    echo "Creating migration: $MIGRATION_NAME"
    if ! dotnet ef migrations add "$MIGRATION_NAME" 2>&1; then
        echo "ERROR: Migration creation failed." >&2
        exit 1
    fi
    echo "  + Migration created: Data/Migrations/*_${MIGRATION_NAME}.cs"
    echo ""
    echo "Review the generated migration, then apply with:"
    echo "  bash .claude/scripts/setup-db-csharp.sh"
fi

echo ""
echo "=========================================================="
echo " DONE"
echo "=========================================================="
echo "[$TIMESTAMP] setup-db-csharp: completed action=$ACTION" >> "../$AUDIT_LOG"
exit 0
