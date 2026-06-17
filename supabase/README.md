# Supabase backend

Version-controlled schema for Market Coverage. Until now the schema lived only
in the Supabase dashboard; new changes go here as numbered SQL migrations so
they're reviewable and repeatable.

```
supabase/
  migrations/
    0001_auth_user_scoping.sql   # add user_id + RLS to per-user tables
```

## Auth foundation rollout

The app now requires sign-in (Supabase Auth, email + password). Roll it out in
this order so nothing breaks:

### 1. Enable email auth (dashboard, one-time)
- **Authentication → Providers → Email**: ensure it's enabled.
- For fast local testing you may turn **"Confirm email" off** (Authentication →
  Sign In / Providers). With it on, a new sign-up must click the emailed link
  before a session is created (the login screen will say "Check your email…").

### 2. Create your account
- Run the app, hit the login screen, choose **Sign up**, create your account.
- Find your user id under **Authentication → Users** (the `id` UUID).

### 3. Apply the user-scoping migration
- Open **`migrations/0001_auth_user_scoping.sql`**, replace every
  `YOUR-USER-UUID` with the id from step 2.
- Run it in **Dashboard → SQL** (or `supabase db push` if you adopt the CLI).
- This backfills your existing leads/driving points/coverage to your account
  and turns on Row-Level Security.

### 4. Tell Claude it's applied
Then I'll:
- switch the `street_coverage` upsert `onConflict` to `('user_id','street_id')`
  (today it's global via `'street_id'`), and
- verify reads/writes still work under RLS.

## Status / honesty note
The SQL here is **drafted but not executed against your project** — I can't reach
your database from the dev environment. Expect to run it once and iterate on any
errors together. The Flutter auth layer (login, gate, sign-out) **is** built and
covered by tests.

## Next phases (not started)
Per the coverage roadmap: per-user data model (this) → PostGIS segmented street
network + server-side matching → route optimization → team mode.
