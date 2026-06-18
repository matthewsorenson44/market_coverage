-- Account backfill helpers for Phase 1.5.
--
-- STATUS: development/backfill helper only. This file is safe to apply because
-- it creates verification views and contains only commented example updates.
--
-- Before enabling RLS:
--   1. Confirm the correct account id from public.accounts.
--   2. Backfill existing development rows with that account id.
--   3. Verify every user-owned table has zero rows with null account_id.
--
-- Do not guess an account id in production. If there is more than one real
-- customer/user, map each row to its correct account before enabling RLS.

create or replace view public.account_backfill_null_summary as
select 'leads' as table_name,
       count(*)::bigint as total_rows,
       count(*) filter (where account_id is null)::bigint as null_account_id_rows
from public.leads
union all
select 'drive_areas',
       count(*)::bigint,
       count(*) filter (where account_id is null)::bigint
from public.drive_areas
union all
select 'missions',
       count(*)::bigint,
       count(*) filter (where account_id is null)::bigint
from public.missions
union all
select 'properties',
       count(*)::bigint,
       count(*) filter (where account_id is null)::bigint
from public.properties
union all
select 'driving_points',
       count(*)::bigint,
       count(*) filter (where account_id is null)::bigint
from public.driving_points
union all
select 'street_coverage',
       count(*)::bigint,
       count(*) filter (where account_id is null)::bigint
from public.street_coverage;

create or replace view public.account_backfill_rows_by_account as
select 'leads' as table_name,
       coalesce(account_id::text, 'NULL') as account_id,
       count(*)::bigint as row_count
from public.leads
group by account_id
union all
select 'drive_areas',
       coalesce(account_id::text, 'NULL'),
       count(*)::bigint
from public.drive_areas
group by account_id
union all
select 'missions',
       coalesce(account_id::text, 'NULL'),
       count(*)::bigint
from public.missions
group by account_id
union all
select 'properties',
       coalesce(account_id::text, 'NULL'),
       count(*)::bigint
from public.properties
group by account_id
union all
select 'driving_points',
       coalesce(account_id::text, 'NULL'),
       count(*)::bigint
from public.driving_points
group by account_id
union all
select 'street_coverage',
       coalesce(account_id::text, 'NULL'),
       count(*)::bigint
from public.street_coverage
group by account_id;

-- Verification queries:
--
-- select * from public.accounts order by created_at;
-- select * from public.account_backfill_null_summary order by table_name;
-- select * from public.account_backfill_rows_by_account order by table_name, account_id;
--
-- Table-specific checks:
--
-- select count(*) as total_rows,
--        count(*) filter (where account_id is null) as null_account_id_rows
-- from public.leads;
--
-- select account_id, count(*) as row_count
-- from public.leads
-- group by account_id
-- order by account_id nulls first;
--
-- Repeat the two queries above for:
--   public.drive_areas
--   public.missions
--   public.properties
--   public.driving_points
--   public.street_coverage

-- Safe one-account development backfill block.
--
-- IMPORTANT:
--   * Confirm the account id first:
--       select * from public.accounts order by created_at;
--   * Replace 00000000-0000-0000-0000-000000000000 with the correct account id.
--   * Updates only rows where account_id is null.
--   * Does not delete rows.
--   * Does not overwrite rows that already have account_id.
--   * Keep RLS disabled until account_backfill_null_summary shows zero nulls.
--
-- begin;
--
-- with target as (
--   select '00000000-0000-0000-0000-000000000000'::uuid as account_id
-- ),
-- current_user_id as (
--   select owner_user_id as user_id
--   from public.accounts
--   where id = (select account_id from target)
-- )
-- update public.leads
-- set account_id = (select account_id from target),
--     created_by = coalesce(created_by, user_id, (select user_id from current_user_id))
-- where account_id is null;
--
-- with target as (
--   select '00000000-0000-0000-0000-000000000000'::uuid as account_id
-- ),
-- current_user_id as (
--   select owner_user_id as user_id
--   from public.accounts
--   where id = (select account_id from target)
-- )
-- update public.drive_areas
-- set account_id = (select account_id from target),
--     created_by = coalesce(created_by, (select user_id from current_user_id))
-- where account_id is null;
--
-- with target as (
--   select '00000000-0000-0000-0000-000000000000'::uuid as account_id
-- ),
-- current_user_id as (
--   select owner_user_id as user_id
--   from public.accounts
--   where id = (select account_id from target)
-- )
-- update public.missions
-- set account_id = (select account_id from target),
--     created_by = coalesce(created_by, (select user_id from current_user_id))
-- where account_id is null;
--
-- with target as (
--   select '00000000-0000-0000-0000-000000000000'::uuid as account_id
-- ),
-- current_user_id as (
--   select owner_user_id as user_id
--   from public.accounts
--   where id = (select account_id from target)
-- )
-- update public.properties
-- set account_id = (select account_id from target),
--     created_by = coalesce(created_by, (select user_id from current_user_id))
-- where account_id is null;
--
-- with target as (
--   select '00000000-0000-0000-0000-000000000000'::uuid as account_id
-- ),
-- current_user_id as (
--   select owner_user_id as user_id
--   from public.accounts
--   where id = (select account_id from target)
-- )
-- update public.driving_points
-- set account_id = (select account_id from target),
--     created_by = coalesce(created_by, user_id, (select user_id from current_user_id))
-- where account_id is null;
--
-- with target as (
--   select '00000000-0000-0000-0000-000000000000'::uuid as account_id
-- ),
-- current_user_id as (
--   select owner_user_id as user_id
--   from public.accounts
--   where id = (select account_id from target)
-- )
-- update public.street_coverage
-- set account_id = (select account_id from target),
--     created_by = coalesce(created_by, user_id, (select user_id from current_user_id))
-- where account_id is null;
--
-- select * from public.account_backfill_null_summary order by table_name;
--
-- commit;
