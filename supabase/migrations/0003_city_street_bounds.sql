-- Phase 1 Street Coverage Intelligence:
-- add bounding columns so the app can load only streets inside the visible map
-- area instead of loading every street path for the selected city.

alter table public.city_streets
  add column if not exists min_lat double precision,
  add column if not exists max_lat double precision,
  add column if not exists min_lng double precision,
  add column if not exists max_lng double precision;

with street_points as (
  select
    city_streets.id,
    case
      when jsonb_typeof(point_value) = 'array'
        then (point_value ->> 0)::double precision
      else coalesce(
        point_value ->> 'lat',
        point_value ->> 'latitude'
      )::double precision
    end as latitude,
    case
      when jsonb_typeof(point_value) = 'array'
        then (point_value ->> 1)::double precision
      else coalesce(
        point_value ->> 'lng',
        point_value ->> 'lon',
        point_value ->> 'longitude'
      )::double precision
    end as longitude
  from public.city_streets
  cross join lateral jsonb_array_elements(city_streets.path::jsonb) point_value
),
street_bounds as (
  select
    id,
    min(latitude) as min_lat,
    max(latitude) as max_lat,
    min(longitude) as min_lng,
    max(longitude) as max_lng
  from street_points
  where latitude is not null
    and longitude is not null
  group by id
)
update public.city_streets
set
  min_lat = street_bounds.min_lat,
  max_lat = street_bounds.max_lat,
  min_lng = street_bounds.min_lng,
  max_lng = street_bounds.max_lng
from street_bounds
where city_streets.id = street_bounds.id;

create index if not exists city_streets_city_bounds_idx
  on public.city_streets (city, min_lat, max_lat, min_lng, max_lng);

create or replace view public.city_street_stats as
select
  city,
  count(*)::integer as total_streets
from public.city_streets
group by city;

grant select on public.city_street_stats to anon, authenticated;
