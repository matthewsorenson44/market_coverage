alter table public.leads
drop constraint if exists leads_source_check;

alter table public.leads
add constraint leads_source_check
check (
  source in (
    'driving',
    'referral',
    'facebook',
    'instagram',
    'tiktok',
    'youtube',
    'x',
    'mailing',
    'bandit_signs',
    'website',
    'manual',
    'csv_import',
    'other'
  )
);
