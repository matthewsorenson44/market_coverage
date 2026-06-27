-- Secure lead delete RPC.
--
-- Why this exists:
--   PostgREST/RLS deletes can silently affect zero rows when policies do not
--   match the live row shape. The Flutter app calls this function first so the
--   database can verify access and delete related lead rows in one place.
--
-- The function does NOT disable RLS and does NOT let users delete arbitrary
-- leads. It only deletes when the signed-in user is tied to the lead by:
--   * account membership, or
--   * user_id, or
--   * created_by.

create or replace function public.app_delete_column_exists(
  target_table text,
  target_column text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = target_table
      and column_name = target_column
  );
$$;

revoke all on function public.app_delete_column_exists(text, text) from public;
grant execute on function public.app_delete_column_exists(text, text)
  to authenticated;

create or replace function public.delete_lead_for_current_user(
  target_lead_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  allowed boolean := false;
  access_conditions text[] := array[]::text[];
  access_clause text;
  deleted_count integer := 0;
  related_table text;
  related_tables text[] := array[
    'lead_photos',
    'tasks'
  ];
begin
  if target_lead_id is null or auth.uid() is null then
    return false;
  end if;

  if to_regclass('public.leads') is null then
    return false;
  end if;

  if public.app_delete_column_exists('leads', 'account_id')
     and to_regclass('public.account_members') is not null
     and public.app_delete_column_exists('account_members', 'account_id')
     and public.app_delete_column_exists('account_members', 'user_id') then
    access_conditions := array_append(
      access_conditions,
      'exists (
        select 1
        from public.account_members as member
        where member.account_id = leads.account_id
          and member.user_id::text = $2::text
      )'
    );
  end if;

  if public.app_delete_column_exists('leads', 'user_id') then
    access_conditions := array_append(
      access_conditions,
      'leads.user_id::text = $2::text'
    );
  end if;

  if public.app_delete_column_exists('leads', 'created_by') then
    access_conditions := array_append(
      access_conditions,
      'leads.created_by::text = $2::text'
    );
  end if;

  if array_length(access_conditions, 1) is null then
    return false;
  end if;

  access_clause := array_to_string(access_conditions, ' or ');

  execute format(
    'select exists (
      select 1
      from public.leads
      where id = $1
        and (%s)
    )',
    access_clause
  )
  into allowed
  using target_lead_id, auth.uid();

  if not coalesce(allowed, false) then
    return false;
  end if;

  foreach related_table in array related_tables loop
    if to_regclass('public.' || related_table) is not null
       and public.app_delete_column_exists(related_table, 'lead_id') then
      execute format(
        'delete from public.%I where lead_id::text = $1::text',
        related_table
      )
      using target_lead_id;
    end if;
  end loop;

  delete from public.leads
  where id = target_lead_id;

  get diagnostics deleted_count = row_count;

  return deleted_count > 0;
end;
$$;

revoke all on function public.delete_lead_for_current_user(uuid) from public;
grant execute on function public.delete_lead_for_current_user(uuid)
  to authenticated;
