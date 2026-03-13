---
globs: ["backend/models/**", "supabase/migrations/**", "backend/services/**", "supabase/seed.sql"]
---

> **Tone:** Apply these patterns automatically. Narrate database decisions in plain English — managers don't need to know SQL details.

## Migrations Only

- Always create database changes as migrations. Narrate: "I created a database migration to add the new table safely."
- Never use ALTER TABLE, CREATE TABLE, or DROP in application code — always in migration files.
- Never modify migration files after they have been applied — always create a new migration instead.
- Test migrations against a clean database before pushing: `supabase db reset`.

## Required Columns

Always include these standard columns in every table. Narrate: "I included the standard columns so we can track when things were created and updated."

```sql
id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
created_at timestamptz DEFAULT now() NOT NULL,
updated_at timestamptz DEFAULT now() NOT NULL,
deleted_at timestamptz DEFAULT NULL
```

- Always add a trigger to auto-update `updated_at` on row modification.
- Always filter by `deleted_at IS NULL` in all queries (soft delete pattern).

## Soft Deletes Only

- Always use soft deletes (mark as deleted rather than removing). Narrate: "I set up soft deletes so data can be recovered if needed."
- Always filter `WHERE deleted_at IS NULL` unless explicitly recovering deleted records.
- Always include the soft delete filter in RLS policies.
- Create a helper function or view that automatically applies the soft delete filter.

## Row Level Security (RLS)

- Always enable Row Level Security on every table. Narrate: "I added security rules so each user only sees their own data."
- Always define RLS policies in the migration that creates the table.
- Always use `auth.uid()` in policies to scope access to the authenticated user.
- Service role operations bypass RLS — use only in backend with explicit justification.
- Always test RLS policies with both authorized and unauthorized users.

## Index Requirements

- Always add an index on every foreign key column. Narrate: "I added indexes so lookups stay fast as your data grows."
- Always add indexes on columns used frequently in WHERE clauses.
- Use composite indexes for multi-column queries (order matters — most selective first).
- Always add indexes in the same migration that creates the table or adds the column.
- Avoid creating unused indexes — they slow down writes.

## N+1 Query Prevention

- Always use supabase-py's query builder with `.select("*, relation(*)")` for related data. Narrate: "I loaded the related data in one query so the page loads faster."
- Never loop over rows and make a query per row.
- If you need data from related tables, always use a single query with joins or embedded selects.
- Review any loop that contains a Supabase client call — it is almost certainly an N+1.

## Transactions

- Always use database functions or RPC calls for multi-step writes (insert parent + children, update + log). Narrate: "I wrapped these changes in a transaction so they either all succeed or all fail."
- Use `supabase.rpc()` for operations that need atomicity.
- Never rely on sequential API calls for data consistency — network failures between calls can corrupt data.

## Query Safety

- Always specify the columns you need — never use `SELECT *`. Narrate: "I selected only the needed columns to keep things efficient."
- Always use the supabase-py query builder — never write raw SQL strings in Python code.
- Always use parameterized queries — never concatenate user input into queries.
- Always limit result sets with `.limit()` — never fetch unbounded data.
- Use `.single()` when expecting exactly one result to fail fast on unexpected multiples.
