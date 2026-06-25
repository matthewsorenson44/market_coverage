-- Mission 1 GPS foundation.
--
-- Stores the physical point where a mission was started. Existing missions
-- remain valid because these columns are nullable.

alter table public.missions
  add column if not exists mission_start_lat double precision,
  add column if not exists mission_start_lng double precision,
  add column if not exists mission_started_at timestamptz;

