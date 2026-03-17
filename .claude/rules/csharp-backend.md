# C# / ASP.NET Core Backend

**Applies when:** `BACKEND_LANGUAGE=csharp` in `.env`. Full spec: `.claude/refs/csharp-backend.md` — read it before writing C# code.

**Key rules (always enforced):**
- BLOCK: Raw SQL string concatenation — use EF Core LINQ or `FromSqlRaw` with parameters only
- BLOCK: Credentials hardcoded in source — use `Environment.GetEnvironmentVariable()` or Key Vault
- BLOCK: Route handler with business logic > 20 lines — logic belongs in `Services/`
- Response envelope: `ApiResponse<T>` with `status`, `data`, `meta.request_id`
- Tests: xUnit + `WebApplicationFactory<Program>`, mock with `Moq`, 80/70 coverage minimum
