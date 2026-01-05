-- SpendSense / Supabase Postgres migrations
-- File: 001_init.sql
-- Execution order:
--   1) 001_init.sql (DDL, types, tables, indexes, triggers)
--   2) 002_rls.sql (enable RLS + commented example policies)
--   3) 003_seed.sql (demo seed data)
--
-- Notes:
-- - This script is intended for PostgreSQL 14+ and Supabase.
-- - It is written to be idempotent: safe to re-run.
-- - In Supabase, `auth.users` exists by default. This schema references it.
-- - If you run this outside Supabase, you must create an `auth.users` equivalent or adjust FKs.

begin;

-- 1) Extensions
create extension if not exists "pgcrypto";

-- 2) Enums (idempotent via DO blocks)
do $$
begin
  if not exists (select 1 from pg_type where typname = 'transaction_type' and typnamespace = 'public'::regnamespace) then
    create type public.transaction_type as enum ('expense', 'income', 'transfer');
  end if;

  if not exists (select 1 from pg_type where typname = 'transaction_status' and typnamespace = 'public'::regnamespace) then
    create type public.transaction_status as enum ('pending', 'cleared', 'void');
  end if;

  if not exists (select 1 from pg_type where typname = 'alert_severity' and typnamespace = 'public'::regnamespace) then
    create type public.alert_severity as enum ('low', 'medium', 'high');
  end if;

  if not exists (select 1 from pg_type where typname = 'alert_kind' and typnamespace = 'public'::regnamespace) then
    create type public.alert_kind as enum ('rule', 'triggered');
  end if;

  if not exists (select 1 from pg_type where typname = 'alert_status' and typnamespace = 'public'::regnamespace) then
    create type public.alert_status as enum ('active', 'paused', 'resolved');
  end if;

  if not exists (select 1 from pg_type where typname = 'budget_period' and typnamespace = 'public'::regnamespace) then
    create type public.budget_period as enum ('monthly');
  end if;

  if not exists (select 1 from pg_type where typname = 'audit_event_type' and typnamespace = 'public'::regnamespace) then
    create type public.audit_event_type as enum (
      'insert',
      'update',
      'delete',
      'auth',
      'access',
      'policy_denied',
      'system'
    );
  end if;
end$$;

-- 3) Tables

-- users (profile table)
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  default_currency char(3) not null default 'USD',
  timezone text not null default 'UTC',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint users_default_currency_chk check (default_currency ~ '^[A-Z]{3}$')
);

create index if not exists users_created_at_idx on public.users (created_at);

-- categories
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  name text not null,
  parent_category_id uuid references public.categories(id) on delete set null,

  color text,
  icon text,
  is_archived boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint categories_unique_name_per_user unique (user_id, name),
  constraint categories_color_format_chk check (
    color is null or color ~ '^#[0-9A-Fa-f]{6}$'
  )
);

create index if not exists categories_user_id_idx on public.categories (user_id);
create index if not exists categories_parent_idx on public.categories (parent_category_id);
create index if not exists categories_user_archived_idx on public.categories (user_id, is_archived);

-- transactions
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  occurred_at timestamptz not null,
  posted_at timestamptz,

  type public.transaction_type not null default 'expense',
  status public.transaction_status not null default 'cleared',

  amount numeric(14,2) not null,
  currency char(3) not null default 'USD',

  merchant text,
  description text,
  memo text,

  category_id uuid references public.categories(id) on delete set null,

  external_source text,
  external_id text,

  is_recurring boolean not null default false,
  tags text[] not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint transactions_currency_chk check (currency ~ '^[A-Z]{3}$'),
  constraint transactions_amount_nonzero_chk check (amount <> 0),
  constraint transactions_external_unique unique (user_id, external_source, external_id)
);

create index if not exists transactions_user_occurred_at_idx on public.transactions (user_id, occurred_at desc);
create index if not exists transactions_user_category_idx on public.transactions (user_id, category_id);
create index if not exists transactions_user_status_idx on public.transactions (user_id, status);
create index if not exists transactions_user_type_idx on public.transactions (user_id, type);

-- budgets
create table if not exists public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  period public.budget_period not null default 'monthly',

  period_start date not null,

  category_id uuid references public.categories(id) on delete set null,

  amount_limit numeric(14,2) not null,
  currency char(3) not null default 'USD',

  alert_threshold_percent numeric(5,2) not null default 90.00,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint budgets_currency_chk check (currency ~ '^[A-Z]{3}$'),
  constraint budgets_amount_positive_chk check (amount_limit > 0),
  constraint budgets_threshold_chk check (alert_threshold_percent between 0 and 100),
  constraint budgets_period_start_chk check (period_start = date_trunc('month', period_start)::date)
);

create unique index if not exists budgets_unique_scope_idx
  on public.budgets (user_id, period, period_start, coalesce(category_id, '00000000-0000-0000-0000-000000000000'::uuid));

create index if not exists budgets_user_period_start_idx on public.budgets (user_id, period_start desc);
create index if not exists budgets_user_category_idx on public.budgets (user_id, category_id);

-- alerts
create table if not exists public.alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  kind public.alert_kind not null default 'rule',
  status public.alert_status not null default 'active',
  severity public.alert_severity not null default 'low',

  title text not null,
  message text,

  rule_type text,
  rule_config jsonb not null default '{}'::jsonb,

  transaction_id uuid references public.transactions(id) on delete set null,
  budget_id uuid references public.budgets(id) on delete set null,

  triggered_at timestamptz,
  resolved_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint alerts_triggered_timestamps_chk check (
    (kind = 'triggered' and triggered_at is not null) or (kind = 'rule')
  )
);

create index if not exists alerts_user_status_idx on public.alerts (user_id, status);
create index if not exists alerts_user_kind_idx on public.alerts (user_id, kind);
create index if not exists alerts_user_severity_idx on public.alerts (user_id, severity);
create index if not exists alerts_user_triggered_at_idx on public.alerts (user_id, triggered_at desc);
create index if not exists alerts_transaction_idx on public.alerts (transaction_id);
create index if not exists alerts_budget_idx on public.alerts (budget_id);

-- audit_log
create table if not exists public.audit_log (
  id bigserial primary key,

  user_id uuid references auth.users(id) on delete set null,

  event_type public.audit_event_type not null,
  entity_table text,
  entity_id uuid,
  action text not null,
  metadata jsonb not null default '{}'::jsonb,

  ip inet,
  user_agent text,

  created_at timestamptz not null default now()
);

create index if not exists audit_log_user_created_at_idx on public.audit_log (user_id, created_at desc);
create index if not exists audit_log_event_type_idx on public.audit_log (event_type);
create index if not exists audit_log_entity_idx on public.audit_log (entity_table, entity_id);

-- 4) updated_at trigger function + triggers (idempotent)
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'set_users_updated_at'
  ) then
    create trigger set_users_updated_at
    before update on public.users
    for each row execute function public.set_updated_at();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgname = 'set_categories_updated_at'
  ) then
    create trigger set_categories_updated_at
    before update on public.categories
    for each row execute function public.set_updated_at();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgname = 'set_transactions_updated_at'
  ) then
    create trigger set_transactions_updated_at
    before update on public.transactions
    for each row execute function public.set_updated_at();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgname = 'set_budgets_updated_at'
  ) then
    create trigger set_budgets_updated_at
    before update on public.budgets
    for each row execute function public.set_updated_at();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgname = 'set_alerts_updated_at'
  ) then
    create trigger set_alerts_updated_at
    before update on public.alerts
    for each row execute function public.set_updated_at();
  end if;
end$$;

commit;
