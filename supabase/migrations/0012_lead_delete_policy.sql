-- Allow authenticated account members to delete leads in their account.
--
-- This is intentionally small. It fixes the common live-db failure where the
-- app can read/update leads but DELETE is blocked by RLS or missing grants.

create or replace function public.app_can_delete_account_lead(
  target_account_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    target_account_id is not null
    and auth.uid() is not null
    and exists (
      select 1
      from public.account_members
      where account_id = target_account_id
        and user_id = auth.uid()
    );
$$;

grant execute on function public.app_can_delete_account_lead(uuid)
  to authenticated;

alter table public.leads enable row level security;

grant select, delete on public.leads to authenticated;

drop policy if exists "leads delete for account members"
  on public.leads;

create policy "leads delete for account members"
  on public.leads
  for delete
  to authenticated
  using (public.app_can_delete_account_lead(account_id));
