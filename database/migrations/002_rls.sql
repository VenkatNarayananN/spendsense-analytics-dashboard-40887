-- SpendSense / Supabase Postgres migrations
-- File: 002_rls.sql
-- Execution order:
--   1) 001_init.sql (DDL)
--   2) 002_rls.sql (this file: enable RLS + commented policies)
--   3) 003_seed.sql (demo seed data)
--
-- Notes:
-- - This file enables Row Level Security (RLS) per table.
-- - Policies are intentionally COMMENTED OUT:
--     * you can uncomment for a permissive demo posture
--     * then later harden as needed (least privilege, role separation, etc.)
-- - On Supabase, policies typically rely on auth.uid().

begin;

alter table public.users enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets enable row level security;
alter table public.alerts enable row level security;
alter table public.audit_log enable row level security;

-- -------------------------------------------------------------------
-- COMMENTED EXAMPLE POLICIES (uncomment to use)
-- -------------------------------------------------------------------

-- USERS (profile)
-- create policy "users_select_own"
-- on public.users
-- for select
-- using (id = auth.uid());
--
-- create policy "users_insert_own"
-- on public.users
-- for insert
-- with check (id = auth.uid());
--
-- create policy "users_update_own"
-- on public.users
-- for update
-- using (id = auth.uid())
-- with check (id = auth.uid());

-- CATEGORIES
-- create policy "categories_select_own"
-- on public.categories
-- for select
-- using (user_id = auth.uid());
--
-- create policy "categories_insert_own"
-- on public.categories
-- for insert
-- with check (user_id = auth.uid());
--
-- create policy "categories_update_own"
-- on public.categories
-- for update
-- using (user_id = auth.uid())
-- with check (user_id = auth.uid());
--
-- create policy "categories_delete_own"
-- on public.categories
-- for delete
-- using (user_id = auth.uid());

-- TRANSACTIONS
-- create policy "transactions_select_own"
-- on public.transactions
-- for select
-- using (user_id = auth.uid());
--
-- create policy "transactions_insert_own"
-- on public.transactions
-- for insert
-- with check (user_id = auth.uid());
--
-- create policy "transactions_update_own"
-- on public.transactions
-- for update
-- using (user_id = auth.uid())
-- with check (user_id = auth.uid());
--
-- create policy "transactions_delete_own"
-- on public.transactions
-- for delete
-- using (user_id = auth.uid());

-- BUDGETS
-- create policy "budgets_select_own"
-- on public.budgets
-- for select
-- using (user_id = auth.uid());
--
-- create policy "budgets_insert_own"
-- on public.budgets
-- for insert
-- with check (user_id = auth.uid());
--
-- create policy "budgets_update_own"
-- on public.budgets
-- for update
-- using (user_id = auth.uid())
-- with check (user_id = auth.uid());
--
-- create policy "budgets_delete_own"
-- on public.budgets
-- for delete
-- using (user_id = auth.uid());

-- ALERTS
-- create policy "alerts_select_own"
-- on public.alerts
-- for select
-- using (user_id = auth.uid());
--
-- create policy "alerts_insert_own"
-- on public.alerts
-- for insert
-- with check (user_id = auth.uid());
--
-- create policy "alerts_update_own"
-- on public.alerts
-- for update
-- using (user_id = auth.uid())
-- with check (user_id = auth.uid());
--
-- create policy "alerts_delete_own"
-- on public.alerts
-- for delete
-- using (user_id = auth.uid());

-- AUDIT LOG (often append-only; typically inserted by server-side code)
-- create policy "audit_log_select_own"
-- on public.audit_log
-- for select
-- using (user_id = auth.uid());
--
-- -- If you must allow client inserts for a demo:
-- create policy "audit_log_insert_own"
-- on public.audit_log
-- for insert
-- with check (user_id = auth.uid());
--
-- -- Common hardening:
-- -- REVOKE UPDATE/DELETE and do not create update/delete policies.

commit;
