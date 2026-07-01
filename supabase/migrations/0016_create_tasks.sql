-- T1 Tasks Data Layer
-- Run manually in Supabase SQL Editor.
--
-- Backfill assumptions: none. This is a new table and starts empty.
-- Ownership follows the current leads pattern with user_id.
-- Future team/account work should migrate this table to account_id alongside leads.

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,
  area_id uuid,
  mission_id uuid,
  title text not null,
  description text,
  status text not null default 'open',
  priority text,
  due_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tasks_status_check check (status in ('open', 'done')),
  constraint tasks_title_not_blank check (length(trim(title)) > 0)
);

create index if not exists tasks_user_id_idx on public.tasks(user_id);
create index if not exists tasks_lead_id_idx on public.tasks(lead_id);
create index if not exists tasks_due_at_idx on public.tasks(due_at);
create index if not exists tasks_status_idx on public.tasks(status);

create or replace function public.set_tasks_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_tasks_updated_at on public.tasks;
create trigger set_tasks_updated_at
before update on public.tasks
for each row execute function public.set_tasks_updated_at();

alter table public.tasks enable row level security;

grant select, insert, update, delete on public.tasks to authenticated;

drop policy if exists "own tasks select" on public.tasks;
create policy "own tasks select"
on public.tasks
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "own tasks insert" on public.tasks;
create policy "own tasks insert"
on public.tasks
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "own tasks update" on public.tasks;
create policy "own tasks update"
on public.tasks
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "own tasks delete" on public.tasks;
create policy "own tasks delete"
on public.tasks
for delete
to authenticated
using (auth.uid() = user_id);
