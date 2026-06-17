-- Make street coverage per-user: replace the global street_id uniqueness with a
-- (user_id, street_id) unique key so two users can independently cover the same
-- street. Requires 0001 (which adds street_coverage.user_id) applied first.
--
-- STATUS: not yet applied / unverified. Run in the Supabase SQL editor after
-- 0001. See supabase/README.md.

-- Drop the existing global uniqueness on street_id.
-- Verify the exact name first with: \d public.street_coverage
-- It is usually a constraint named street_coverage_street_id_key; if it is a
-- plain index instead, use `drop index if exists ...` accordingly.
alter table public.street_coverage
  drop constraint if exists street_coverage_street_id_key;

-- Per-user uniqueness — supports the app's onConflict: 'user_id,street_id'.
create unique index if not exists street_coverage_user_street_key
  on public.street_coverage (user_id, street_id);
