# Street data import pipeline

This app uses `city_streets` as shared reference data for Street Coverage
Intelligence. Do not hand-draw or fake street rows; import real street
centerlines from a GIS source.

## Expected `city_streets` shape

Each row should contain:

- `id`: stable unique segment id, usually city + source feature id
- `city`: one supported city name such as `Tulsa`
- `street_name`: display name from the source data
- `path`: JSON array of `{ "lat": number, "lng": number }` points
- `min_lat`: smallest latitude in `path`
- `max_lat`: largest latitude in `path`
- `min_lng`: smallest longitude in `path`
- `max_lng`: largest longitude in `path`

The app uses the bounds columns to load only visible streets for the selected
city.

## Source data

Primary source: INCOG ArcGIS REST Services Directory.

Use:

```text
https://map11.incog.org/arcgis11wa/rest/services/RoadCenterlines_updated/FeatureServer/0/query
```

This is a real road centerline layer. Query it as GeoJSON with `outSR=4326` so
coordinates are returned as longitude/latitude.

Useful fields:

- `OBJECTID`
- `NGUID_RDCL`
- `LINK_ID`
- `INCOGID`
- `FullName`
- `Label`
- `Street`
- `StreetType`
- `City_L`
- `City_R`
- `PostComm_L`
- `PostComm_R`

## Import tool

The converter is:

```powershell
dart run tool/import_city_streets_geojson.dart --help
```

It accepts either:

- `--input path/to/file.geojson`
- `--arcgis-url <query-url> --where <where-clause>`

It writes a CSV that matches `city_streets`, and it can also upload directly to
Supabase when `--upload` is provided.

## Sample Tulsa dry run

Run this first. It reads real INCOG centerline data and prints a summary without
writing to Supabase:

```powershell
dart run tool/import_city_streets_geojson.dart `
  --city Tulsa `
  --arcgis-url https://map11.incog.org/arcgis11wa/rest/services/RoadCenterlines_updated/FeatureServer/0/query `
  --where "City_L = 'TULSA' OR City_R = 'TULSA'" `
  --dry-run
```

## Create a CSV for review

```powershell
dart run tool/import_city_streets_geojson.dart `
  --city Tulsa `
  --arcgis-url https://map11.incog.org/arcgis11wa/rest/services/RoadCenterlines_updated/FeatureServer/0/query `
  --where "City_L = 'TULSA' OR City_R = 'TULSA'" `
  --output build/imports/tulsa_city_streets.csv
```

Open the CSV and spot-check:

- `city` is `Tulsa`
- `street_name` is populated
- `path` is a JSON array of lat/lng objects
- bounds columns are populated

## Upload directly to Supabase

Use a service role key only in your local terminal. Never put it in source code
or commit it.

```powershell
$env:SUPABASE_URL = "https://YOUR-PROJECT.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY = "YOUR-SERVICE-ROLE-KEY"

dart run tool/import_city_streets_geojson.dart `
  --city Tulsa `
  --arcgis-url https://map11.incog.org/arcgis11wa/rest/services/RoadCenterlines_updated/FeatureServer/0/query `
  --where "City_L = 'TULSA' OR City_R = 'TULSA'" `
  --output build/imports/tulsa_city_streets.csv `
  --upload
```

The upload uses `city_streets?on_conflict=id`, so rerunning the same import
updates existing rows with the same stable ids.

## Repeat for other supported cities

Use the same command and change `--city` plus the city name in the `--where`
clause:

```text
Broken Arrow
Bixby
Jenks
Sand Springs
Collinsville
Skiatook
```

For a wider match, especially where mailing/community fields are more reliable,
use:

```sql
City_L = 'CITY NAME'
OR City_R = 'CITY NAME'
OR PostComm_L = 'CITY NAME'
OR PostComm_R = 'CITY NAME'
```

## Verify the import

Run these in Supabase SQL Editor:

```sql
select city, count(*) as street_count
from public.city_streets
group by city
order by city;
```

```sql
select *
from public.city_street_stats
order by city;
```

```sql
select id, city, street_name, min_lat, max_lat, min_lng, max_lng
from public.city_streets
where city = 'Tulsa'
limit 10;
```

```sql
select count(*) as rows_missing_bounds
from public.city_streets
where city = 'Tulsa'
  and (
    min_lat is null
    or max_lat is null
    or min_lng is null
    or max_lng is null
  );
```

Expected result:

- `Tulsa` appears in `city_streets`
- `city_street_stats` has a non-zero `total_streets` for `Tulsa`
- `rows_missing_bounds` is `0`
- Driving Mode no longer shows the empty state for `Tulsa`
- Red uncovered streets appear in Tulsa, and covered streets turn green after
  route tracking or simulated drives match them
