create extension if not exists pgcrypto;

create table if not exists market_cities (
  id uuid primary key default gen_random_uuid(),
  city text not null,
  city_name text,
  state text not null default 'Oklahoma',
  state_code text not null default 'OK',
  county text,
  display_name text,
  rank_in_state int,
  population int,
  latitude double precision,
  longitude double precision,
  market_status text not null default 'planned',
  parcel_service_url text,
  parcel_service_layer int default 0,
  parcel_where_clause text,
  street_import_status text default 'none',
  street_import_date timestamptz,
  parcel_service_verified boolean default false,
  parcel_service_last_checked timestamptz,
  rollout_status text default 'planned',
  sort_order int default 99,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table market_cities add column if not exists city text;
alter table market_cities add column if not exists city_name text;
alter table market_cities add column if not exists state text default 'Oklahoma';
alter table market_cities add column if not exists state_code text default 'OK';
alter table market_cities add column if not exists county text;
alter table market_cities add column if not exists display_name text;
alter table market_cities add column if not exists rank_in_state int;
alter table market_cities add column if not exists population int;
alter table market_cities add column if not exists latitude double precision;
alter table market_cities add column if not exists longitude double precision;
alter table market_cities add column if not exists market_status text default 'planned';
alter table market_cities add column if not exists parcel_service_url text;
alter table market_cities add column if not exists parcel_service_layer int default 0;
alter table market_cities add column if not exists parcel_where_clause text;
alter table market_cities add column if not exists street_import_status text default 'none';
alter table market_cities add column if not exists street_import_date timestamptz;
alter table market_cities add column if not exists parcel_service_verified boolean default false;
alter table market_cities add column if not exists parcel_service_last_checked timestamptz;
alter table market_cities add column if not exists rollout_status text default 'planned';
alter table market_cities add column if not exists sort_order int default 99;
alter table market_cities add column if not exists notes text;
alter table market_cities add column if not exists created_at timestamptz default now();
alter table market_cities add column if not exists updated_at timestamptz default now();

update market_cities
set city = coalesce(nullif(city, ''), nullif(city_name, '')),
    city_name = coalesce(nullif(city_name, ''), nullif(city, '')),
    state = coalesce(nullif(state, ''), 'Oklahoma'),
    state_code = coalesce(nullif(state_code, ''), case when state = 'OK' then 'OK' else state end, 'OK'),
    display_name = coalesce(nullif(display_name, ''), nullif(city, ''), nullif(city_name, '')),
    market_status = coalesce(nullif(market_status, ''), nullif(rollout_status, ''), 'planned'),
    updated_at = now()
where city is null
   or city_name is null
   or state is null
   or state_code is null
   or display_name is null
   or market_status is null;

alter table market_cities alter column city set not null;
alter table market_cities alter column state set not null;
alter table market_cities alter column state_code set not null;
alter table market_cities alter column market_status set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'market_cities_market_status_check'
  ) then
    alter table market_cities
      add constraint market_cities_market_status_check
      check (market_status in ('live', 'building', 'planned', 'disabled'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'market_cities_street_import_status_check'
  ) then
    alter table market_cities
      add constraint market_cities_street_import_status_check
      check (street_import_status in ('complete', 'partial', 'pending', 'none'));
  end if;
end $$;

create unique index if not exists market_cities_city_state_code_idx
  on market_cities (city, state_code);

insert into market_cities (
  city,
  city_name,
  state,
  state_code,
  county,
  display_name,
  rank_in_state,
  market_status,
  parcel_service_url,
  parcel_service_layer,
  street_import_status,
  parcel_service_verified,
  rollout_status,
  sort_order
)
values
(
  'Owasso',
  'Owasso',
  'Oklahoma',
  'OK',
  'Tulsa',
  'Owasso, OK',
  null,
  'live',
  'https://map11.incog.org/arcgis11wa/rest/services/Parcels_TulsaCo/FeatureServer/0/query',
  0,
  'complete',
  true,
  'live',
  1
),
(
  'Tulsa',
  'Tulsa',
  'Oklahoma',
  'OK',
  'Tulsa',
  'Tulsa, OK',
  null,
  'building',
  'https://map11.incog.org/arcgis11wa/rest/services/Parcels_TulsaCo/FeatureServer/0/query',
  0,
  'none',
  true,
  'building',
  2
),
(
  'Broken Arrow',
  'Broken Arrow',
  'Oklahoma',
  'OK',
  'Tulsa',
  'Broken Arrow, OK',
  null,
  'planned',
  null,
  0,
  'none',
  false,
  'planned',
  3
),
(
  'Bixby',
  'Bixby',
  'Oklahoma',
  'OK',
  'Tulsa',
  'Bixby, OK',
  null,
  'planned',
  null,
  0,
  'none',
  false,
  'planned',
  4
)
on conflict (city, state_code) do update set
  city_name = excluded.city_name,
  state = excluded.state,
  county = excluded.county,
  display_name = excluded.display_name,
  market_status = excluded.market_status,
  parcel_service_url = coalesce(excluded.parcel_service_url, market_cities.parcel_service_url),
  parcel_service_layer = excluded.parcel_service_layer,
  street_import_status = excluded.street_import_status,
  parcel_service_verified = excluded.parcel_service_verified,
  rollout_status = excluded.rollout_status,
  sort_order = excluded.sort_order,
  updated_at = now();

