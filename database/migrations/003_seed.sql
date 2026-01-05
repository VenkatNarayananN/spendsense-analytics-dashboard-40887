-- SpendSense / Supabase Postgres migrations
-- File: 003_seed.sql
-- Execution order:
--   1) 001_init.sql
--   2) 002_rls.sql
--   3) 003_seed.sql (this file)
--
-- IMPORTANT (Supabase Auth dependency):
-- - This seed script expects *three existing* Supabase Auth users in auth.users.
-- - Provide their UUIDs using psql variables, or edit the \set lines below before running.
--
-- How to run (psql):
--   psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 \
--     -v demo_user_1='00000000-0000-0000-0000-000000000001' \
--     -v demo_user_2='00000000-0000-0000-0000-000000000002' \
--     -v demo_user_3='00000000-0000-0000-0000-000000000003' \
--     -f 003_seed.sql
--
-- How to run (Supabase SQL editor):
--   Replace :'demo_user_1' / :'demo_user_2' / :'demo_user_3' with real auth.users UUIDs.
--
-- Idempotency:
-- - Uses ON CONFLICT for stable natural keys (user_id + category name, user+budget scope index).
-- - Transactions use a deterministic external_id scheme and insert with external_source='seed'
--   so reruns do not duplicate (unique constraint on (user_id, external_source, external_id)).

begin;

-- -------------------------------------------------------------------
-- 0) Demo user IDs (override via psql -v demo_user_*=...).
-- -------------------------------------------------------------------
-- These are placeholders; they MUST match real rows in auth.users.
\set demo_user_1 '00000000-0000-0000-0000-000000000001'
\set demo_user_2 '00000000-0000-0000-0000-000000000002'
\set demo_user_3 '00000000-0000-0000-0000-000000000003'

-- -------------------------------------------------------------------
-- 1) Seed user profiles
-- -------------------------------------------------------------------
with demo_users as (
  select :'demo_user_1'::uuid as id, 'Avery Chen'::text as display_name, 'USD'::char(3) as default_currency, 'America/Los_Angeles'::text as timezone
  union all
  select :'demo_user_2'::uuid as id, 'Jordan Patel'::text as display_name, 'USD'::char(3) as default_currency, 'America/New_York'::text as timezone
  union all
  select :'demo_user_3'::uuid as id, 'Sam Rivera'::text as display_name, 'USD'::char(3) as default_currency, 'Europe/London'::text as timezone
)
insert into public.users (id, display_name, default_currency, timezone)
select id, display_name, default_currency, timezone
from demo_users
on conflict (id) do update
set
  display_name = excluded.display_name,
  default_currency = excluded.default_currency,
  timezone = excluded.timezone,
  updated_at = now();

-- -------------------------------------------------------------------
-- 2) Seed categories (10+; mix income/expense; user-scoped)
-- -------------------------------------------------------------------
with demo_users as (
  select :'demo_user_1'::uuid as user_id
  union all select :'demo_user_2'::uuid
  union all select :'demo_user_3'::uuid
),
cats as (
  -- expenses
  select user_id, 'Groceries'::text as name, '#34D399'::text as color, '🛒'::text as icon from demo_users union all
  select user_id, 'Dining'   , '#F59E0B', '🍽️' from demo_users union all
  select user_id, 'Coffee'   , '#A78BFA', '☕'  from demo_users union all
  select user_id, 'Transport', '#60A5FA', '🚇'  from demo_users union all
  select user_id, 'Gas'      , '#93C5FD', '⛽'  from demo_users union all
  select user_id, 'Rent'     , '#F472B6', '🏠'  from demo_users union all
  select user_id, 'Utilities', '#94A3B8', '💡'  from demo_users union all
  select user_id, 'Phone'    , '#38BDF8', '📱'  from demo_users union all
  select user_id, 'Internet' , '#22C55E', '🌐'  from demo_users union all
  select user_id, 'Shopping' , '#FB7185', '🛍️' from demo_users union all
  select user_id, 'Health'   , '#10B981', '🏥'  from demo_users union all
  select user_id, 'Fitness'  , '#F97316', '🏋️' from demo_users union all
  select user_id, 'Travel'   , '#0EA5E9', '✈️'  from demo_users union all
  select user_id, 'Entertainment', '#8B5CF6', '🎬' from demo_users union all
  -- income
  select user_id, 'Salary'   , '#16A34A', '💰' from demo_users union all
  select user_id, 'Interest' , '#14B8A6', '🏦' from demo_users union all
  -- transfers / adjustments
  select user_id, 'Transfer' , '#64748B', '🔁' from demo_users union all
  select user_id, 'Refunds'  , '#4ADE80', '↩️' from demo_users
)
insert into public.categories (user_id, name, color, icon)
select user_id, name, color, icon
from cats
on conflict (user_id, name) do update
set
  color = excluded.color,
  icon = excluded.icon,
  updated_at = now();

-- -------------------------------------------------------------------
-- 3) Seed budgets: 3 months per user, overall + a few category budgets
-- -------------------------------------------------------------------
with demo_users as (
  select :'demo_user_1'::uuid as user_id
  union all select :'demo_user_2'::uuid
  union all select :'demo_user_3'::uuid
),
months as (
  -- last 2 months + current month (3 months total), month aligned
  select date_trunc('month', now())::date as period_start
  union all select (date_trunc('month', now()) - interval '1 month')::date
  union all select (date_trunc('month', now()) - interval '2 months')::date
),
overall as (
  select
    u.user_id,
    'monthly'::public.budget_period as period,
    m.period_start,
    null::uuid as category_id,
    -- vary by user to look realistic
    case
      when u.user_id = :'demo_user_1'::uuid then 3200.00
      when u.user_id = :'demo_user_2'::uuid then 4200.00
      else 2800.00
    end as amount_limit,
    'USD'::char(3) as currency,
    90.00::numeric(5,2) as alert_threshold_percent
  from demo_users u cross join months m
),
cat_scoped as (
  select
    u.user_id,
    'monthly'::public.budget_period as period,
    m.period_start,
    c.id as category_id,
    case c.name
      when 'Groceries' then 550.00
      when 'Dining' then 300.00
      when 'Shopping' then 250.00
      when 'Transport' then 220.00
      else 200.00
    end as amount_limit,
    'USD'::char(3) as currency,
    85.00::numeric(5,2) as alert_threshold_percent
  from demo_users u
  cross join months m
  join public.categories c
    on c.user_id = u.user_id
   and c.name in ('Groceries','Dining','Shopping','Transport')
)
insert into public.budgets (user_id, period, period_start, category_id, amount_limit, currency, alert_threshold_percent, is_active)
select user_id, period, period_start, category_id, amount_limit, currency, alert_threshold_percent, true
from (
  select * from overall
  union all
  select * from cat_scoped
) b
on conflict on constraint budgets_unique_scope_idx do update
set
  amount_limit = excluded.amount_limit,
  currency = excluded.currency,
  alert_threshold_percent = excluded.alert_threshold_percent,
  is_active = excluded.is_active,
  updated_at = now();

-- -------------------------------------------------------------------
-- 4) Seed alert rules + a few triggered alerts
-- -------------------------------------------------------------------
with demo_users as (
  select :'demo_user_1'::uuid as user_id
  union all select :'demo_user_2'::uuid
  union all select :'demo_user_3'::uuid
),
rules as (
  select
    user_id,
    'rule'::public.alert_kind as kind,
    'active'::public.alert_status as status,
    'medium'::public.alert_severity as severity,
    'Large purchase threshold'::text as title,
    'Notify me when a single transaction exceeds my chosen amount.'::text as message,
    'large_transaction'::text as rule_type,
    jsonb_build_object('threshold', 120.00, 'currency', 'USD') as rule_config
  from demo_users
  union all
  select
    user_id,
    'rule',
    'active',
    'low',
    'Budget nearing limit',
    'Warn me when any tracked budget crosses the alert threshold.',
    'category_budget',
    jsonb_build_object('threshold_percent', 85.00)
  from demo_users
  union all
  select
    user_id,
    'rule',
    'paused',
    'high',
    'Unusual merchant activity',
    'Flag spending with merchants that are uncommon for me.',
    'merchant_anomaly',
    jsonb_build_object('window_days', 30, 'min_amount', 75.00)
  from demo_users
)
insert into public.alerts (user_id, kind, status, severity, title, message, rule_type, rule_config)
select user_id, kind, status, severity, title, message, rule_type, rule_config
from rules
on conflict do nothing;

-- -------------------------------------------------------------------
-- 5) Seed transactions (300+ over last 6 months), realistic merchants
--     - Uses deterministic series-based generation with slight variability.
--     - Uses external_source='seed' and external_id='seed-<user>-<date>-<seq>' for idempotency.
-- -------------------------------------------------------------------
-- Helper CTEs for users and category IDs
with demo_users as (
  select 1 as uidx, :'demo_user_1'::uuid as user_id
  union all select 2, :'demo_user_2'::uuid
  union all select 3, :'demo_user_3'::uuid
),
cat_map as (
  select u.user_id, c.name, c.id
  from demo_users u
  join public.categories c on c.user_id = u.user_id
),
-- Generate 6 months daily grid; then sample multiple transactions per day via lateral series.
days as (
  select
    u.user_id,
    (date_trunc('day', now()) - (gs.day_offset || ' days')::interval)::timestamptz as day_ts,
    gs.day_offset
  from demo_users u
  cross join generate_series(0, 179) as gs(day_offset)
),
-- For each day, generate a varying number of "events" based on deterministic pattern
events as (
  select
    d.user_id,
    d.day_ts,
    d.day_offset,
    es.event_seq,
    -- deterministic "bucket" to choose merchant/category patterns
    ( (d.day_offset + es.event_seq * 7 + abs(hashtext(d.user_id::text)) % 17) % 100 ) as bucket
  from days d
  join lateral generate_series(
    1,
    case
      when (d.day_offset % 7) in (5,6) then 3  -- weekends slightly more
      when (d.day_offset % 14) = 0 then 4      -- every ~2 weeks a heavier day
      else 2
    end
  ) as es(event_seq) on true
),
-- Merchant & category selection using bucket ranges
classified as (
  select
    e.user_id,
    -- spread within the day (08:00..21:00)
    (e.day_ts + make_interval(hours => 8 + (e.bucket % 14), mins => (e.bucket * 3) % 60)) as occurred_at,
    -- posted_at: 0-2 days after (often same day)
    (e.day_ts + make_interval(days => (e.bucket % 3), hours => 14)) as posted_at,
    case
      when e.bucket between 0 and 4 then 'income'
      when e.bucket between 5 and 8 then 'transfer'
      else 'expense'
    end::public.transaction_type as type,
    case
      when e.bucket % 20 = 0 then 'pending'
      else 'cleared'
    end::public.transaction_status as status,
    -- Choose category name
    case
      when e.bucket between 0 and 4 then 'Salary'
      when e.bucket between 5 and 8 then 'Transfer'
      when e.bucket between 9 and 16 then 'Groceries'
      when e.bucket between 17 and 24 then 'Dining'
      when e.bucket between 25 and 30 then 'Coffee'
      when e.bucket between 31 and 36 then 'Transport'
      when e.bucket between 37 and 40 then 'Gas'
      when e.bucket between 41 and 44 then 'Shopping'
      when e.bucket between 45 and 48 then 'Utilities'
      when e.bucket between 49 and 52 then 'Phone'
      when e.bucket between 53 and 56 then 'Internet'
      when e.bucket between 57 and 60 then 'Health'
      when e.bucket between 61 and 64 then 'Fitness'
      when e.bucket between 65 and 68 then 'Entertainment'
      when e.bucket between 69 and 72 then 'Travel'
      when e.bucket between 73 and 76 then 'Refunds'
      else 'Dining'
    end as category_name,
    -- Merchant selection
    case
      when e.bucket between 0 and 4 then 'SpendSense Payroll'
      when e.bucket between 5 and 8 then 'Bank Transfer'
      when e.bucket between 9 and 16 then (array['Whole Foods','Trader Joe''s','Safeway','Kroger','ALDI','Costco'])[1 + (e.bucket % 6)]
      when e.bucket between 17 and 24 then (array['Chipotle','Sweetgreen','Shake Shack','Panera Bread','Local Bistro','Sushi Spot'])[1 + (e.bucket % 6)]
      when e.bucket between 25 and 30 then (array['Starbucks','Blue Bottle Coffee','Dunkin''','Peet''s Coffee','Local Coffee Bar','Cafe Nero'])[1 + (e.bucket % 6)]
      when e.bucket between 31 and 36 then (array['Uber','Lyft','MTA','TfL','BART','City Transit'])[1 + (e.bucket % 6)]
      when e.bucket between 37 and 40 then (array['Shell','Chevron','BP','Exxon'])[1 + (e.bucket % 4)]
      when e.bucket between 41 and 44 then (array['Amazon','Target','Walmart','Apple Store'])[1 + (e.bucket % 4)]
      when e.bucket between 45 and 48 then (array['PG&E','Con Edison','National Grid','E.ON'])[1 + (e.bucket % 4)]
      when e.bucket between 49 and 52 then (array['Verizon','AT&T','T-Mobile','O2'])[1 + (e.bucket % 4)]
      when e.bucket between 53 and 56 then (array['Comcast','Spectrum','Verizon Fios','BT'])[1 + (e.bucket % 4)]
      when e.bucket between 57 and 60 then (array['CVS Pharmacy','Walgreens','City Clinic','Teladoc'])[1 + (e.bucket % 4)]
      when e.bucket between 61 and 64 then (array['Equinox','Planet Fitness','ClassPass','Local Gym'])[1 + (e.bucket % 4)]
      when e.bucket between 65 and 68 then (array['Netflix','Spotify','AMC Theatres','Steam'])[1 + (e.bucket % 4)]
      when e.bucket between 69 and 72 then (array['Delta Airlines','United','Airbnb','Booking.com'])[1 + (e.bucket % 4)]
      when e.bucket between 73 and 76 then (array['Amazon','Target','Uber','Starbucks'])[1 + (e.bucket % 4)]
      else 'Local Merchant'
    end as merchant,
    -- Description/memo
    case
      when e.bucket between 0 and 4 then 'Monthly salary deposit'
      when e.bucket between 5 and 8 then 'Transfer between accounts'
      when e.bucket between 73 and 76 then 'Refund processed'
      when e.bucket % 13 = 0 then 'Subscription renewal'
      when e.bucket % 17 = 0 then 'Point-of-sale purchase'
      else 'Card purchase'
    end as description,
    case
      when e.bucket % 13 = 0 then 'recurring: true'
      when e.bucket between 69 and 72 then 'travel expense'
      else null
    end as memo,
    -- Amount generation by type/category (income positive, expense negative-ish but schema allows any sign).
    -- We'll use conventional: expenses negative, income positive, transfers +/- mixed, refunds positive.
    round(
      case
        when e.bucket between 0 and 4 then 4200 + (e.bucket * 17)  -- salary deposits
        when e.bucket between 5 and 8 then (case when e.bucket % 2 = 0 then 250 else -250 end) + (e.bucket * 3)
        when e.bucket between 73 and 76 then 12 + (e.bucket % 25)  -- refunds positive
        when e.bucket between 37 and 40 then -(35 + (e.bucket % 40))  -- gas
        when e.bucket between 45 and 48 then -(80 + (e.bucket % 120)) -- utilities
        when e.bucket between 49 and 56 then -(45 + (e.bucket % 60))  -- phone/internet
        when e.bucket between 41 and 44 then -(20 + (e.bucket % 180)) -- shopping
        when e.bucket between 69 and 72 then -(120 + (e.bucket % 900))-- travel
        when e.bucket between 65 and 68 then -(10 + (e.bucket % 35))  -- entertainment
        when e.bucket between 25 and 30 then -(4 + (e.bucket % 10))   -- coffee
        when e.bucket between 17 and 24 then -(12 + (e.bucket % 55))  -- dining
        when e.bucket between 9 and 16 then -(18 + (e.bucket % 110))  -- groceries
        else -(8 + (e.bucket % 75))
      end
    , 2) as amount,
    (e.bucket % 13 = 0) as is_recurring,
    e.bucket
  from events e
),
enriched as (
  select
    c.user_id,
    c.occurred_at,
    c.posted_at,
    c.type,
    c.status,
    c.amount::numeric(14,2) as amount,
    'USD'::char(3) as currency,
    c.merchant,
    c.description,
    c.memo,
    cm.id as category_id,
    -- tags: vary deterministically
    case
      when c.is_recurring then array['subscription']
      when c.bucket between 69 and 72 then array['travel']
      when c.bucket between 9 and 16 then array['needs','food']
      when c.bucket between 17 and 24 then array['food','social']
      when c.bucket between 41 and 44 then array['shopping']
      else array[]::text[]
    end as tags,
    c.is_recurring
  from classified c
  left join cat_map cm
    on cm.user_id = c.user_id
   and cm.name = c.category_name
),
to_insert as (
  select
    e.*,
    'seed'::text as external_source,
    -- Deterministic external_id: seed-<user>-<yyyymmdd>-<hhmm>-<hashbucket>
    (
      'seed-' ||
      replace(e.user_id::text,'-','') || '-' ||
      to_char(e.occurred_at, 'YYYYMMDD-HH24MI') || '-' ||
      lpad((abs(hashtext(e.merchant || e.description || e.amount::text)) % 100000)::text, 5, '0')
    ) as external_id
  from enriched e
)
insert into public.transactions (
  user_id,
  occurred_at,
  posted_at,
  type,
  status,
  amount,
  currency,
  merchant,
  description,
  memo,
  category_id,
  external_source,
  external_id,
  is_recurring,
  tags
)
select
  user_id,
  occurred_at,
  posted_at,
  type,
  status,
  amount,
  currency,
  merchant,
  description,
  memo,
  category_id,
  external_source,
  external_id,
  is_recurring,
  tags
from to_insert
on conflict (user_id, external_source, external_id) do nothing;

-- -------------------------------------------------------------------
-- 6) Create a handful of triggered alerts tied to real seeded transactions
-- -------------------------------------------------------------------
with demo_users as (
  select :'demo_user_1'::uuid as user_id
  union all select :'demo_user_2'::uuid
  union all select :'demo_user_3'::uuid
),
big_spend as (
  -- pick 2 big expenses per user from last 60 days
  select
    t.user_id,
    t.id as transaction_id,
    t.occurred_at as triggered_at,
    t.amount,
    t.merchant,
    row_number() over (partition by t.user_id order by t.amount asc) as rn -- amount likely negative for expenses; asc = "most negative"
  from public.transactions t
  join demo_users u on u.user_id = t.user_id
  where t.occurred_at >= now() - interval '60 days'
    and t.type = 'expense'
    and t.status = 'cleared'
)
insert into public.alerts (
  user_id, kind, status, severity, title, message, rule_type, rule_config,
  transaction_id, triggered_at, created_at, updated_at
)
select
  b.user_id,
  'triggered'::public.alert_kind,
  'active'::public.alert_status,
  'high'::public.alert_severity,
  'Large purchase detected'::text,
  format('A large purchase of %s USD at %s was detected.', abs(b.amount)::numeric(14,2), coalesce(b.merchant,'Unknown'))::text,
  'large_transaction'::text,
  jsonb_build_object('threshold', 120.00, 'detected_amount', abs(b.amount)),
  b.transaction_id,
  b.triggered_at,
  now(),
  now()
from big_spend b
where b.rn <= 2
on conflict do nothing;

-- -------------------------------------------------------------------
-- 7) Seed audit_log entries (append-only) corresponding to seed events
-- -------------------------------------------------------------------
-- Minimal audit: one "system seed" event per table per user, plus some transaction-level inserts.
insert into public.audit_log (user_id, event_type, entity_table, entity_id, action, metadata, created_at)
select
  u.id,
  'system'::public.audit_event_type,
  'users'::text,
  u.id,
  'seed_user_profile'::text,
  jsonb_build_object('source','seed','display_name', u.display_name),
  now()
from public.users u
where u.id in (:'demo_user_1'::uuid, :'demo_user_2'::uuid, :'demo_user_3'::uuid)
on conflict do nothing;

insert into public.audit_log (user_id, event_type, entity_table, action, metadata, created_at)
select
  du.user_id,
  'system'::public.audit_event_type,
  'categories'::text,
  'seed_categories'::text,
  jsonb_build_object('source','seed','count', (select count(*) from public.categories c where c.user_id = du.user_id)),
  now()
from (select :'demo_user_1'::uuid as user_id union all select :'demo_user_2'::uuid union all select :'demo_user_3'::uuid) du;

insert into public.audit_log (user_id, event_type, entity_table, action, metadata, created_at)
select
  du.user_id,
  'system'::public.audit_event_type,
  'budgets'::text,
  'seed_budgets'::text,
  jsonb_build_object('source','seed','months', 3),
  now()
from (select :'demo_user_1'::uuid as user_id union all select :'demo_user_2'::uuid union all select :'demo_user_3'::uuid) du;

-- Transaction insert audit samples: 10 most recent per user (to keep audit volume reasonable)
with demo_users as (
  select :'demo_user_1'::uuid as user_id
  union all select :'demo_user_2'::uuid
  union all select :'demo_user_3'::uuid
),
recent_tx as (
  select
    t.user_id, t.id as entity_id, t.occurred_at, t.amount, t.merchant, t.category_id,
    row_number() over (partition by t.user_id order by t.occurred_at desc) as rn
  from public.transactions t
  join demo_users u on u.user_id = t.user_id
  where t.external_source = 'seed'
)
insert into public.audit_log (user_id, event_type, entity_table, entity_id, action, metadata, created_at)
select
  r.user_id,
  'insert'::public.audit_event_type,
  'transactions'::text,
  r.entity_id,
  'seed_transaction'::text,
  jsonb_build_object(
    'source','seed',
    'amount', r.amount,
    'merchant', r.merchant,
    'occurred_at', r.occurred_at,
    'category_id', r.category_id
  ),
  now()
from recent_tx r
where r.rn <= 10;

commit;

-- -------------------------------------------------------------------
-- Quick sanity checks (optional; safe to keep commented)
-- -------------------------------------------------------------------
-- select count(*) as users from public.users;
-- select user_id, count(*) as categories from public.categories group by user_id order by categories desc;
-- select user_id, count(*) as tx_count from public.transactions group by user_id order by tx_count desc;
-- select count(*) as alerts from public.alerts;
-- select count(*) as audit_entries from public.audit_log;
