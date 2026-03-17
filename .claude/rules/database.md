---
globs: ["backend/models/**", "supabase/migrations/**", "backend/services/**", "supabase/seed.sql"]
---

## Migrations Only

- All schema changes as migrations — never ALTER/CREATE/DROP in app code
- Never modify applied migrations — create new ones instead
- Test with `supabase db reset` before pushing

## Required Columns

Every table: `id uuid DEFAULT gen_random_uuid() PRIMARY KEY`, `created_at timestamptz DEFAULT now() NOT NULL`, `updated_at timestamptz DEFAULT now() NOT NULL`, `deleted_at timestamptz DEFAULT NULL`. Add `updated_at` trigger. Filter `deleted_at IS NULL` in all queries.

## Soft Deletes

- Mark as deleted, never remove. Filter `WHERE deleted_at IS NULL` everywhere including RLS policies.

## Row Level Security

- Enable RLS on every table. Define policies in the CREATE TABLE migration. Use `auth.uid()` to scope access. Service role bypasses RLS — backend only with justification. Test with authorized and unauthorized users.

## Indexes

- Index every FK column and frequent WHERE columns. Composite indexes: most selective first. Add in same migration as table/column creation.

## N+1 Prevention

- Use `.select("*, relation(*)")` for related data. Never loop+query. Review any loop with a Supabase call.

## Transactions

- Use database functions or `supabase.rpc()` for multi-step writes. Never rely on sequential API calls.

## Query Safety

- Specify columns needed — no `SELECT *`. Use supabase-py query builder — no raw SQL. Parameterized queries only. `.limit()` on all queries. `.single()` when expecting one result.

## Audit Log RLS

- Admins: full SELECT access to all audit log entries
- Non-admin users: SELECT only their own entries (`user_id = auth.uid()`)
- No UPDATE or DELETE policies — audit logs are append-only (INSERT via triggers only)
- Service role bypasses RLS for trigger-based inserts
