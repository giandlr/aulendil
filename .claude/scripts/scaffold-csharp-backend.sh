#!/usr/bin/env bash
set -uo pipefail

# Scaffold ASP.NET Core 8 Minimal API backend directory structure
# Usage: bash .claude/scripts/scaffold-csharp-backend.sh
# Triggered automatically by bootstrap.sh when BACKEND_LANGUAGE=csharp
# Exit 0 = success, Exit 1 = error

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
AUDIT_LOG=".claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
echo "[$TIMESTAMP] scaffold-csharp-backend: started" >> "$AUDIT_LOG"

echo "=========================================================="
echo " SCAFFOLD C# BACKEND (ASP.NET Core 8 Minimal APIs)"
echo "=========================================================="
echo ""

APP_NAME="${APP_NAME:-$(basename "$(pwd)" | tr '-' '_' | tr '[:upper:]' '[:lower:]')}"
APP_PASCAL="$(echo "$APP_NAME" | sed 's/_\([a-z]\)/\U\1/g; s/^\([a-z]\)/\U\1/g')"

echo "  App name:   $APP_NAME"
echo "  Namespace:  $APP_PASCAL"
echo ""

if [ -d "backend" ]; then
    echo "  backend/ already exists — skipping scaffold"
    exit 0
fi

# Check dotnet CLI
if ! command -v dotnet &>/dev/null; then
    echo "ERROR: dotnet CLI not found." >&2
    echo "       Install .NET 8 SDK from https://dotnet.microsoft.com/download" >&2
    exit 1
fi

# ----------------------------------------------------------
# Scaffold using dotnet new (creates minimal web project)
# ----------------------------------------------------------
echo "  Scaffolding with dotnet new..."
dotnet new web -n backend --framework net8.0 --no-restore 2>&1 | tail -3
echo "  + Created backend/ via dotnet new"

# ----------------------------------------------------------
# Add required directories on top of dotnet scaffold
# ----------------------------------------------------------
mkdir -p backend/{Routes,Services,Models,Data/Migrations,Middleware,Tests/Unit,Tests/Integration}
echo "  + Created directory structure"

# ----------------------------------------------------------
# Rename generated program file to avoid conflicts
# (dotnet new web creates Program.cs with a minimal stub)
# ----------------------------------------------------------
echo "  + Directory layout:"
echo "      backend/Routes/          Endpoint maps (< 20 lines each)"
echo "      backend/Services/        Business logic"
echo "      backend/Models/          Request/response DTOs"
echo "      backend/Data/            EF Core DbContext + Migrations"
echo "      backend/Middleware/      Correlation ID + error handling"
echo "      backend/Tests/           xUnit test project"

# ----------------------------------------------------------
# Add NuGet packages
# ----------------------------------------------------------
echo ""
echo "  Adding NuGet packages..."
cd backend
dotnet add package Microsoft.AspNetCore.Authentication.JwtBearer 2>&1 | tail -2
dotnet add package Microsoft.EntityFrameworkCore 2>&1 | tail -2
dotnet add package Microsoft.EntityFrameworkCore.Design 2>&1 | tail -2
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL 2>&1 | tail -2
echo "  + Packages added"
cd ..

# ----------------------------------------------------------
# Create Tests project and solution
# ----------------------------------------------------------
if ! dotnet new xunit -n Tests -o backend/Tests --framework net8.0 --no-restore 2>&1 | tail -3; then
    echo "  WARNING: Could not create xUnit test project"
fi

if ! dotnet new sln -n "$APP_NAME" --force 2>&1 | tail -3; then
    echo "  WARNING: Could not create solution file"
else
    dotnet sln add backend/backend.csproj 2>/dev/null || true
    dotnet sln add backend/Tests/Tests.csproj 2>/dev/null || true
    echo "  + Created solution file"
fi

echo ""
echo "C# backend scaffolded. See .claude/rules/csharp-backend.md for conventions."
echo ""
echo "Next:"
echo "  cd backend && dotnet restore"
echo "  cd backend && dotnet build"
echo "  cd backend && dotnet run"

echo "[$TIMESTAMP] scaffold-csharp-backend: completed" >> "$AUDIT_LOG"
exit 0
