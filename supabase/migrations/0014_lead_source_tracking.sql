-- Lead source tracking data layer.
-- Run manually in Supabase SQL Editor.
--
-- Canonical source values:
--   driving, manual, referral, facebook, website, csv_import, other

alter table public.leads
add column if not exists source text not null default 'driving';

alter table public.leads
drop constraint if exists leads_source_check;

update public.leads
set source = case lower(trim(coalesce(source, '')))
  when 'driving' then 'driving'
  when 'drive' then 'driving'
  when 'driving for dollars' then 'driving'
  when 'd4d' then 'driving'
  when 'manual' then 'manual'
  when 'manual add' then 'manual'
  when 'manual lead' then 'manual'
  when 'referral' then 'referral'
  when 'facebook' then 'facebook'
  when 'fb' then 'facebook'
  when 'website' then 'website'
  when 'web' then 'website'
  when 'web form' then 'website'
  when 'csv_import' then 'csv_import'
  when 'csv import' then 'csv_import'
  when 'csv' then 'csv_import'
  when 'other' then 'other'
  when 'direct mail' then 'other'
  when 'cold call' then 'other'
  else 'driving'
end
where source is null
  or source not in (
    'driving',
    'manual',
    'referral',
    'facebook',
    'website',
    'csv_import',
    'other'
  );

alter table public.leads
alter column source set default 'driving';

alter table public.leads
alter column source set not null;

alter table public.leads
add constraint leads_source_check
check (
  source in (
    'driving',
    'manual',
    'referral',
    'facebook',
    'website',
    'csv_import',
    'other'
  )
);
