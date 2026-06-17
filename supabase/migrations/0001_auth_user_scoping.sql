-- Auth foundation: scope existing data to the signed-in user and enforce it
-- with Row-Level Security.
--
-- STATUS: not yet applied / unverified. Run this in the Supabase SQL editor
-- (Dashboard -> SQL) AFTER you have created your account via the app's login
-- screen. See supabase/README.md for the full runbook.
--
-- Tables touched: leads, driving_points, street_coverage.
-- city_streets is shared reference data and stays world-readable (no user_id).

-- 1. Add a nullable owner column to each per-user table.
alter table public.leads
  add column if not exists user_id uuid references auth.users (id);
alter table public.driving_points
  add column if not exists user_id uuid references auth.users (id);
alter table public.street_coverage
  add column if not exists user_id uuid references auth.users (id);

-- 2. Backfill existing rows to your account.
--    Replace 'YOUR-USER-UUID' with your id from Authentication -> Users.
update public.leads           set user_id = 'YOUR-USER-UUID' where user_id is null;
update public.driving_points  set user_id = 'YOUR-USER-UUID' where user_id is null;
update public.street_coverage set user_id = 'YOUR-USER-UUID' where user_id is null;

-- 3. Default new rows to the inserting user, so the app does not have to send
--    user_id explicitly.
alter table public.leads           alter column user_id set default auth.uid();
alter table public.driving_points  alter column user_id set default auth.uid();
alter table public.street_coverage alter column user_id set default auth.uid();

-- 4. (Optional, after backfill is confirmed) require ownership going forward.
-- alter table public.leads           alter column user_id set not null;
-- alter table public.driving_points  alter column user_id set not null;
-- alter table public.street_coverage alter column user_id set not null;

-- 5. Enable RLS and restrict every row to its owner.
alter table public.leads           enable row level security;
alter table public.driving_points  enable row level security;
alter table public.street_coverage enable row level security;

create policy "own leads" on public.leads
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own driving_points" on public.driving_points
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own street_coverage" on public.street_coverage
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 6. Keep the shared street network readable by any signed-in user.
alter table public.city_streets enable row level security;
create policy "city_streets readable" on public.city_streets
  for select using (true);

-- AFTER this migration is applied, tell Claude so it can:
--   * switch the street_coverage upsert onConflict to ('user_id','street_id')
--     so coverage is deduped per user instead of globally, and
--   * verify inserts still succeed under RLS.
