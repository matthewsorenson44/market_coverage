# Market Catalog Import

Market Coverage OS can list planned markets before street or property data is loaded. A market appearing in the catalog does not mean it is ready to drive.

## Readiness Rules

- Ready: street rows and property rows exist.
- Partial: street rows or property rows exist, but not both.
- Planned: catalog row exists, but no useful street/property data exists.
- Missing Data: the market is not planned but still has no useful street/property data.

## Recommended Source

Use official U.S. Census city/town population estimates for city rankings. Do not hand-enter or guess rankings.

Download or prepare a verified CSV with the top 5 incorporated places per state using this format:

```csv
state_code,state_name,rank,city,population,latitude,longitude
OK,Oklahoma,1,Oklahoma City,702767,35.4676,-97.5164
OK,Oklahoma,2,Tulsa,411867,36.1540,-95.9928
```

Latitude and longitude are optional. Population is optional but recommended.

## Generate Import SQL

From the project root:

```powershell
dart run tool/import_market_cities.dart `
  --input C:\path\to\top_5_markets.csv `
  --output build\imports\market_cities_seed.sql
```

Then open `build/imports/market_cities_seed.sql`, copy it into the Supabase SQL Editor, and run it.

The generated SQL upserts rows into `market_cities` using `(city, state_code)` and defaults imported markets to `market_status = 'planned'`. It does not mark any market Ready.

## Verify

After import:

1. Open the app.
2. Go to Areas.
3. Confirm Market Coverage shows planned markets.
4. Open the market picker from Drive.
5. Search by city or state.
6. Confirm newly imported markets show Planned unless street/property data exists.

