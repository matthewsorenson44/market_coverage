# Account Backfill Runbook

Use this when old development rows have `account_id = null` and are hidden by
the app's account-scoped queries.

Run these statements manually in the Supabase SQL editor. Do not enable RLS yet.

## 1. Find Your Account ID

Run this first and copy the `account_id` for your current user.

```sql
select
  a.id as account_id,
  a.name as account_name,
  a.owner_user_id,
  u.email as owner_email,
  a.created_at
from public.accounts a
join auth.users u on u.id = a.owner_user_id
order by a.created_at;
```

## 2. Check Rows That Still Need Backfill

This shows total rows and rows where `account_id` is still null for each
user-owned table.

```sql
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
from public.street_coverage
order by table_name;
```

Optional detail view by account:

```sql
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
group by account_id
order by table_name, account_id;
```

## 3. Safe Backfill

Paste your real `account_id` into `_target_account_id` before running.

This block:
- raises an error if the account does not exist
- updates only rows where `account_id is null`
- does not delete anything
- does not overwrite non-null `account_id` values
- backfills `created_by` only when a table has that column and it is null

```sql
begin;

do $$
declare
  _target_account_id uuid := 'PASTE-YOUR-ACCOUNT-ID-HERE'::uuid;
  _target_user_id uuid;
  _table_name text;
  _has_created_by boolean;
  _updated_rows integer;
  _owned_tables text[] := array[
    'leads',
    'drive_areas',
    'missions',
    'properties',
    'driving_points',
    'street_coverage'
  ];
begin
  select owner_user_id
  into _target_user_id
  from public.accounts
  where id = _target_account_id;

  if _target_user_id is null then
    raise exception 'Invalid account_id: %. No matching row exists in public.accounts.',
      _target_account_id;
  end if;

  foreach _table_name in array _owned_tables loop
    select exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = _table_name
        and column_name = 'created_by'
    )
    into _has_created_by;

    if _has_created_by then
      execute format(
        'update public.%I
         set account_id = $1,
             created_by = coalesce(created_by, $2)
         where account_id is null',
        _table_name
      )
      using _target_account_id, _target_user_id;
    else
      execute format(
        'update public.%I
         set account_id = $1
         where account_id is null',
        _table_name
      )
      using _target_account_id;
    end if;

    get diagnostics _updated_rows = row_count;
    raise notice 'Backfilled public.% rows: %', _table_name, _updated_rows;
  end loop;
end $$;

commit;
```

## 4. Verify After Backfill

Run this after the backfill. Every `null_account_id_rows` value should be `0`
before any RLS work happens.

```sql
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
from public.street_coverage
order by table_name;
```

Also confirm rows are now grouped under your account:

```sql
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
group by account_id
order by table_name, account_id;
```

## Warnings

- Do not enable RLS yet.
- Do not backfill shared reference tables such as `city_streets` or
  `city_street_stats`.
- Do not run this if you are unsure which account owns the old rows.
- If there is more than one real customer/user in the database, map rows to the
  correct account instead of assigning every null row to one account.
- RLS comes later, after verification shows zero null `account_id` rows in every
  user-owned table.
