# C# / ASP.NET Core Backend Conventions

These rules apply when `BACKEND_LANGUAGE=csharp` is set in `.env`.

## Response Envelope

All endpoints return the same JSON structure as the Python stack:

```json
{"status": "ok|error", "data": ..., "meta": {"request_id": "..."}}
```

Use the shared `ApiResponse<T>` record type defined in `Models/ApiResponse.cs`:

```csharp
public record ApiResponse<T>(string Status, T? Data, ApiMeta Meta);
public record ApiMeta(string RequestId);
```

Return helpers: `ApiResponse.Ok(data, meta)` / `ApiResponse.Error(message, meta)`.

## Route Handlers

- **BLOCK:** Route handler with business logic > 20 lines. Logic belongs in `Services/`.
- Route files in `Routes/` map endpoints and delegate to services — nothing more.
- **WARN:** Missing `.RequireAuthorization()` or `[Authorize]` on non-public endpoints.

## ORM / Database

- **BLOCK:** Raw SQL string concatenation. Use EF Core LINQ queries or `FromSqlRaw` with parameterized arguments (`{0}`, `@param`) only — never string interpolation in SQL.
- All DB access goes through `Data/AppDbContext.cs`.
- EF Core migrations only — never ALTER/CREATE/DROP in application code.
- Soft deletes: filter `WHERE DeletedAt IS NULL` in every query via a global query filter.

## Auth

- JWT verification via `Microsoft.AspNetCore.Authentication.JwtBearer`.
- In Vercel/local mode: verify Supabase-issued JWT (RS256) against Supabase JWKS endpoint.
- In Azure mode: verify Azure Entra ID token or fall back to `X-Forwarded-Email` from OAuth2 Proxy (same dual-mode pattern as Python — see `.claude/rules/auth.md`).
- **BLOCK:** Connection string, JWT secret, or API key hardcoded in source. Read from `Environment.GetEnvironmentVariable()` or Azure Key Vault reference.

## Error Handling

- Global exception handler middleware in `Middleware/ErrorHandlingMiddleware.cs`.
- Generate `request_id` (Guid) at middleware level — attach to logs and every response.
- Log full exception server-side with `ILogger`. Return only correlation ID + generic message to client.
- Never return stack traces to clients.

## Testing

- **WARN:** xUnit test method without at least one `Assert.*` call.
- Use `WebApplicationFactory<Program>` for integration tests.
- Mock dependencies with `Moq` — never hit external services from unit tests.
- Coverage: `coverlet` collector + `ReportGenerator`. Minimum 80% line, 70% branch.

## Lint / Format

```
cd backend && dotnet format --verify-no-changes   # CI check (exit 1 if diff)
cd backend && dotnet format                        # Auto-fix formatting
```

## Dev Commands

```
cd backend && dotnet run                                              # Start dev server
cd backend && dotnet test --collect:"XPlat Code Coverage"            # Run tests with coverage
cd backend && dotnet format --verify-no-changes                      # Lint
cd backend && dotnet ef database update                               # Apply EF migrations
cd backend && dotnet ef migrations add [migration_name]               # New migration
```

## Directory Contract

```
backend/                         # when BACKEND_LANGUAGE=csharp
├── Program.cs                   # Minimal API entry + DI setup
├── Routes/                      # Endpoint maps (< 20 lines each, no logic)
├── Services/                    # Business logic layer
├── Models/                      # Request/response DTOs (record types preferred)
├── Data/
│   ├── AppDbContext.cs          # EF Core DbContext + soft-delete global filter
│   └── Migrations/              # EF Core migrations (committed to git)
├── Middleware/                  # Auth, correlation ID, error handling
├── Tests/
│   ├── Unit/
│   └── Integration/
└── backend.csproj
```

## What to Enforce Automatically

BLOCK:
- Raw SQL string concatenation in EF Core calls
- Connection string, JWT secret, or any credential hardcoded in source
- Route handler with business logic over 20 lines

WARN:
- Missing `RequireAuthorization()` / `[Authorize]` on non-public endpoints
- xUnit test without assertion

## Rate Limiting

- Use `AspNetCoreRateLimit` NuGet package (same middleware pattern as Python's `slowapi`)
- Configure in `Program.cs` via `builder.Services.AddInMemoryRateLimiting()` or Redis-backed
- Apply `[EnableRateLimiting("fixed")]` on controllers or `RequireRateLimiting("fixed")` on endpoints
- Stricter limits on auth endpoints (login, register, reset)

## Azure RLS (DEPLOY_TARGET=azure)

- Filter queries by email column via `app.current_user_email` PostgreSQL setting
- `AppDbContext` sets `SET app.current_user_email` on connection open via `DbConnection.StateChange` event
- Global query filter in EF Core: `.HasQueryFilter(e => EF.Property<string>(e, "Email") == _currentUserEmail)`

## Custom JWT Claims

- Extract role from `ClaimsPrincipal` in middleware: `context.User.FindFirstValue(ClaimTypes.Role)`
- Map Supabase custom claims to standard .NET claim types in `JwtBearerEvents.OnTokenValidated`
- Use `[Authorize(Roles = "Admin,Manager")]` or policy-based auth for route protection

## Idempotency

- Implement `Idempotency-Key` header middleware in `Middleware/IdempotencyMiddleware.cs`
- Store `(key, response_body, status_code, expires_at)` in `idempotency_keys` table via EF Core
- Return cached response for duplicate keys within TTL (default: 24 hours)
- Only applies to POST/PUT/PATCH — GET and DELETE are naturally idempotent

## Service Role Key

- Read from `Environment.GetEnvironmentVariable("SUPABASE_SERVICE_ROLE_KEY")` only
- **BLOCK:** Service role key in `appsettings.json`, `appsettings.Development.json`, or any committed config file
- In Azure mode: use Azure Key Vault references (`@Microsoft.KeyVault(...)`) in Container App env vars
