-- Market Coverage OS RLS/security audit.
--
-- Flutter tables found in lib/main.dart:
--   accounts, account_members, leads, driving_points, street_coverage,
--   city_streets, city_street_stats, market_cities, markets, drive_areas,
--   properties, missions, weekly_plans.
--
-- Flutter lead photo Storage:
--   bucket: lead-photos
--   path:   <auth_user_id>/<lead_id>/<timestamp>.<extension>
--
-- This migration is defensive: optional tables only receive policies when they
-- exist, and policies are based on the columns each table actually has.

create or replace function public.app_has_column(
  p_table_name text,
  p_column_name text
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
      and table_name = p_table_name
      and column_name = p_column_name
  );
$$;

create or replace function public.app_is_account_member(target_account_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  allowed boolean := false;
begin
  if target_account_id is null or auth.uid() is null then
    return false;
  end if;

  if to_regclass('public.account_members') is not null then
    execute
      'select exists (
        select 1
        from public.account_members
        where account_id = $1 and user_id = $2
      )'
      into allowed
      using target_account_id, auth.uid();
  end if;

  if allowed then
    return true;
  end if;

  if to_regclass('public.accounts') is not null
     and public.app_has_column('accounts', 'owner_user_id') then
    execute
      'select exists (
        select 1
        from public.accounts
        where id = $1 and owner_user_id = $2
      )'
      into allowed
      using target_account_id, auth.uid();
  end if;

  return coalesce(allowed, false);
end;
$$;

create or replace function public.app_owns_account(target_account_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  allowed boolean := false;
begin
  if target_account_id is null or auth.uid() is null then
    return false;
  end if;

  if to_regclass('public.accounts') is null
     or not public.app_has_column('accounts', 'owner_user_id') then
    return false;
  end if;

  execute
    'select exists (
      select 1
      from public.accounts
      where id = $1 and owner_user_id = $2
    )'
    into allowed
    using target_account_id, auth.uid();

  return coalesce(allowed, false);
end;
$$;

create or replace function public.app_can_access_drive_area(
  target_drive_area_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  allowed boolean := false;
begin
  if target_drive_area_id is null or auth.uid() is null then
    return false;
  end if;

  if to_regclass('public.drive_areas') is null then
    return false;
  end if;

  execute
    'select exists (
      select 1
      from public.drive_areas
      where id = $1
        and (
          (public.app_has_column(''drive_areas'', ''account_id'')
            and public.app_is_account_member(account_id))
          or (public.app_has_column(''drive_areas'', ''created_by'')
            and created_by = $2)
        )
    )'
    into allowed
    using target_drive_area_id, auth.uid();

  return coalesce(allowed, false);
end;
$$;

create or replace function public.app_can_access_lead(target_lead_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  allowed boolean := false;
begin
  if target_lead_id is null or auth.uid() is null then
    return false;
  end if;

  if to_regclass('public.leads') is null then
    return false;
  end if;

  execute
    'select exists (
      select 1
      from public.leads
      where id = $1
        and (
          (public.app_has_column(''leads'', ''account_id'')
            and public.app_is_account_member(account_id))
          or (public.app_has_column(''leads'', ''user_id'')
            and user_id = $2)
          or (public.app_has_column(''leads'', ''created_by'')
            and created_by = $2)
        )
    )'
    into allowed
    using target_lead_id, auth.uid();

  return coalesce(allowed, false);
end;
$$;

create or replace function public.app_can_access_lead_photo_object(
  object_name text,
  require_owner_folder boolean default false
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, storage
as $$
declare
  folders text[];
  owner_folder text;
  lead_id_text text;
  lead_uuid uuid;
begin
  if object_name is null or auth.uid() is null then
    return false;
  end if;

  folders := storage.foldername(object_name);
  owner_folder := folders[1];
  lead_id_text := folders[2];

  if owner_folder is null or owner_folder = '' then
    return false;
  end if;

  if require_owner_folder and owner_folder <> auth.uid()::text then
    return false;
  end if;

  if owner_folder = auth.uid()::text and lead_id_text is null then
    return true;
  end if;

  begin
    lead_uuid := lead_id_text::uuid;
  exception
    when others then
      return owner_folder = auth.uid()::text;
  end;

  if require_owner_folder then
    return public.app_can_access_lead(lead_uuid);
  end if;

  return owner_folder = auth.uid()::text
    or public.app_can_access_lead(lead_uuid);
end;
$$;

revoke all on function public.app_has_column(text, text) from public;
revoke all on function public.app_is_account_member(uuid) from public;
revoke all on function public.app_owns_account(uuid) from public;
revoke all on function public.app_can_access_drive_area(uuid) from public;
revoke all on function public.app_can_access_lead(uuid) from public;
revoke all on function public.app_can_access_lead_photo_object(text, boolean)
  from public;

grant execute on function public.app_has_column(text, text) to authenticated;
grant execute on function public.app_is_account_member(uuid) to authenticated;
grant execute on function public.app_owns_account(uuid) to authenticated;
grant execute on function public.app_can_access_drive_area(uuid)
  to authenticated;
grant execute on function public.app_can_access_lead(uuid) to authenticated;
grant execute on function public.app_can_access_lead_photo_object(text, boolean)
  to authenticated;

-- Add missing ownership columns to app-owned tables when the table exists.
do $$
declare
  table_name text;
  account_tables text[] := array[
    'leads',
    'driving_points',
    'drive_points',
    'street_coverage',
    'drive_areas',
    'areas',
    'properties',
    'missions',
    'weekly_plans',
    'drives',
    'tasks',
    'lead_photos'
  ];
  user_tables text[] := array[
    'leads',
    'driving_points',
    'drive_points',
    'street_coverage',
    'drives',
    'tasks',
    'lead_photos'
  ];
begin
  foreach table_name in array account_tables loop
    if to_regclass('public.' || table_name) is not null
       and to_regclass('public.accounts') is not null
       and not public.app_has_column(table_name, 'account_id') then
      execute format(
        'alter table public.%I add column account_id uuid references public.accounts(id)',
        table_name
      );
    end if;

    if to_regclass('public.' || table_name) is not null
       and not public.app_has_column(table_name, 'created_by') then
      execute format(
        'alter table public.%I add column created_by uuid references auth.users(id) default auth.uid()',
        table_name
      );
    end if;
  end loop;

  foreach table_name in array user_tables loop
    if to_regclass('public.' || table_name) is not null
       and not public.app_has_column(table_name, 'user_id') then
      execute format(
        'alter table public.%I add column user_id uuid references auth.users(id) default auth.uid()',
        table_name
      );
    end if;
  end loop;
end $$;

-- Account tables.
do $$
begin
  if to_regclass('public.accounts') is not null then
    if not public.app_has_column('accounts', 'owner_user_id') then
      alter table public.accounts
        add column owner_user_id uuid references auth.users(id) default auth.uid();
    end if;

    alter table public.accounts enable row level security;

    drop policy if exists "accounts select for members" on public.accounts;
    drop policy if exists "accounts insert by owner" on public.accounts;
    drop policy if exists "accounts update by owner" on public.accounts;
    drop policy if exists "accounts delete by owner" on public.accounts;

    create policy "accounts select for members"
      on public.accounts
      for select
      to authenticated
      using (
        public.app_is_account_member(id)
        or owner_user_id = auth.uid()
      );

    create policy "accounts insert by owner"
      on public.accounts
      for insert
      to authenticated
      with check (owner_user_id = auth.uid());

    create policy "accounts update by owner"
      on public.accounts
      for update
      to authenticated
      using (owner_user_id = auth.uid())
      with check (owner_user_id = auth.uid());

    create policy "accounts delete by owner"
      on public.accounts
      for delete
      to authenticated
      using (owner_user_id = auth.uid());
  end if;

  if to_regclass('public.account_members') is not null then
    if not public.app_has_column('account_members', 'account_id')
       and to_regclass('public.accounts') is not null then
      alter table public.account_members
        add column account_id uuid references public.accounts(id);
    end if;

    if not public.app_has_column('account_members', 'user_id') then
      alter table public.account_members
        add column user_id uuid references auth.users(id) default auth.uid();
    end if;

    if not public.app_has_column('account_members', 'role') then
      alter table public.account_members
        add column role text default 'member';
    end if;

    alter table public.account_members enable row level security;

    drop policy if exists "account members select for account" on public.account_members;
    drop policy if exists "account members insert by owner" on public.account_members;
    drop policy if exists "account members update by owner" on public.account_members;
    drop policy if exists "account members delete by owner" on public.account_members;

    create policy "account members select for account"
      on public.account_members
      for select
      to authenticated
      using (
        user_id = auth.uid()
        or public.app_owns_account(account_id)
      );

    create policy "account members insert by owner"
      on public.account_members
      for insert
      to authenticated
      with check (public.app_owns_account(account_id));

    create policy "account members update by owner"
      on public.account_members
      for update
      to authenticated
      using (public.app_owns_account(account_id))
      with check (public.app_owns_account(account_id));

    create policy "account members delete by owner"
      on public.account_members
      for delete
      to authenticated
      using (
        user_id = auth.uid()
        or public.app_owns_account(account_id)
      );
  end if;
end $$;

-- Generic account/user scoped policies for mutable app tables.
do $$
declare
  table_name text;
  table_names text[] := array[
    'leads',
    'driving_points',
    'drive_points',
    'street_coverage',
    'drive_areas',
    'areas',
    'properties',
    'missions',
    'weekly_plans',
    'drives',
    'tasks',
    'lead_photos'
  ];
  conditions text[];
  access_clause text;
begin
  foreach table_name in array table_names loop
    if to_regclass('public.' || table_name) is null then
      continue;
    end if;

    conditions := array[]::text[];

    if public.app_has_column(table_name, 'account_id') then
      conditions := array_append(
        conditions,
        'public.app_is_account_member(account_id)'
      );
    end if;

    if public.app_has_column(table_name, 'user_id') then
      conditions := array_append(conditions, 'user_id = auth.uid()');
    end if;

    if public.app_has_column(table_name, 'created_by') then
      conditions := array_append(conditions, 'created_by = auth.uid()');
    end if;

    if public.app_has_column(table_name, 'owner_user_id') then
      conditions := array_append(conditions, 'owner_user_id = auth.uid()');
    end if;

    if public.app_has_column(table_name, 'drive_area_id') then
      conditions := array_append(
        conditions,
        'public.app_can_access_drive_area(drive_area_id)'
      );
    end if;

    if public.app_has_column(table_name, 'lead_id') then
      conditions := array_append(
        conditions,
        'public.app_can_access_lead(lead_id)'
      );
    end if;

    if array_length(conditions, 1) is null then
      continue;
    end if;

    access_clause := array_to_string(conditions, ' or ');

    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'drop policy if exists "app scoped access" on public.%I',
      table_name
    );
    execute format(
      'create policy "app scoped access" on public.%I for all to authenticated using (%s) with check (%s)',
      table_name,
      access_clause,
      access_clause
    );
  end loop;
end $$;

-- Profiles/users if they exist.
do $$
begin
  if to_regclass('public.profiles') is not null then
    alter table public.profiles enable row level security;

    drop policy if exists "profiles own row" on public.profiles;

    if public.app_has_column('profiles', 'id') then
      create policy "profiles own row"
        on public.profiles
        for all
        to authenticated
        using (id = auth.uid())
        with check (id = auth.uid());
    elsif public.app_has_column('profiles', 'user_id') then
      create policy "profiles own row"
        on public.profiles
        for all
        to authenticated
        using (user_id = auth.uid())
        with check (user_id = auth.uid());
    end if;
  end if;

  if to_regclass('public.users') is not null then
    alter table public.users enable row level security;

    drop policy if exists "users own row" on public.users;

    if public.app_has_column('users', 'id') then
      create policy "users own row"
        on public.users
        for all
        to authenticated
        using (id = auth.uid())
        with check (id = auth.uid());
    elsif public.app_has_column('users', 'user_id') then
      create policy "users own row"
        on public.users
        for all
        to authenticated
        using (user_id = auth.uid())
        with check (user_id = auth.uid());
    end if;
  end if;
end $$;

-- Shared/reference tables used by maps, markets, and imports.
do $$
declare
  table_name text;
  table_names text[] := array[
    'city_streets',
    'market_cities',
    'markets'
  ];
begin
  foreach table_name in array table_names loop
    if to_regclass('public.' || table_name) is not null then
      execute format('alter table public.%I enable row level security', table_name);
      execute format(
        'drop policy if exists "reference data readable" on public.%I',
        table_name
      );
      execute format(
        'create policy "reference data readable" on public.%I for select to anon, authenticated using (true)',
        table_name
      );
    end if;
  end loop;

  if to_regclass('public.city_street_stats') is not null then
    grant select on public.city_street_stats to anon, authenticated;
  end if;
end $$;

-- Secure private Storage bucket for lead photos.
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'lead-photos',
  'lead-photos',
  false,
  10485760,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "lead photos readable"
  on storage.objects;
drop policy if exists "lead photos insert for owned leads"
  on storage.objects;
drop policy if exists "lead photos update for owned leads"
  on storage.objects;
drop policy if exists "lead photos delete for owned leads"
  on storage.objects;
drop policy if exists "lead photos readable by signed in users"
  on storage.objects;
drop policy if exists "lead photos insert by signed in users"
  on storage.objects;
drop policy if exists "lead photos update by signed in users"
  on storage.objects;
drop policy if exists "lead photos delete by signed in users"
  on storage.objects;
drop policy if exists "lead photos user folder read"
  on storage.objects;
drop policy if exists "lead photos user folder insert"
  on storage.objects;
drop policy if exists "lead photos user folder update"
  on storage.objects;
drop policy if exists "lead photos user folder delete"
  on storage.objects;
drop policy if exists "lead photos mvp read"
  on storage.objects;
drop policy if exists "lead photos mvp insert"
  on storage.objects;
drop policy if exists "lead photos mvp update"
  on storage.objects;
drop policy if exists "lead photos mvp delete"
  on storage.objects;

create policy "lead photos user folder read"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'lead-photos'
    and public.app_can_access_lead_photo_object(name, false)
  );

create policy "lead photos user folder insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'lead-photos'
    and public.app_can_access_lead_photo_object(name, true)
  );

create policy "lead photos user folder update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'lead-photos'
    and public.app_can_access_lead_photo_object(name, true)
  )
  with check (
    bucket_id = 'lead-photos'
    and public.app_can_access_lead_photo_object(name, true)
  );

create policy "lead photos user folder delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'lead-photos'
    and public.app_can_access_lead_photo_object(name, true)
  );
