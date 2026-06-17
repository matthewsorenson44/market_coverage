# Codex task: Phase 2 — per-user data model

You are implementing one well-scoped phase of an existing Flutter + Supabase
app (`market_coverage`). Claude designed this; you implement it. Stay strictly
in scope — do not refactor or "improve" unrelated code.

## Context

The app just gained authentication (Supabase Auth + a login wall). Migration
`supabase/migrations/0001_auth_user_scoping.sql` adds a `user_id` column
(default `auth.uid()`) and Row-Level Security to `leads`, `driving_points`, and
`street_coverage`.

Two things remain to make data truly per-user:

1. **Coverage de-dup is still global.** `saveStreetCoverage` upserts with
   `onConflict: 'street_id'`, so one user covering a street blocks every other
   user from recording it. It must become per-user `(user_id, street_id)`.
2. **Writes don't stamp `user_id`.** Inserts rely on nothing today; stamp the
   signed-in user explicitly so intent is clear and the composite upsert works.

> **Deploy coupling:** these app changes require migrations `0001` **and** the
> new `0002` (below) to be applied to Supabase. They ship together.

## Task 1 — new migration

Create `supabase/migrations/0002_street_coverage_per_user.sql`:

```sql
-- Make street coverage per-user: replace the global street_id uniqueness with a
-- (user_id, street_id) unique key so two users can independently cover the same
-- street. Requires 0001 (which adds street_coverage.user_id) applied first.

-- Drop the existing global uniqueness on street_id.
-- Verify the exact name first with: \d public.street_coverage
-- It is usually a constraint named street_coverage_street_id_key; if it is an
-- index instead, use `drop index if exists ...` accordingly.
alter table public.street_coverage
  drop constraint if exists street_coverage_street_id_key;

-- Per-user uniqueness — supports onConflict: 'user_id,street_id'.
create unique index if not exists street_coverage_user_street_key
  on public.street_coverage (user_id, street_id);
```

## Task 2 — stamp `user_id` and fix the upsert (lib/main.dart)

All four edits are inside existing methods. Add
`'user_id': supabase.auth.currentUser?.id` to each write map. The app is gated
behind login, so `currentUser` is non-null at these call sites.

### 2a. `saveStreetCoverage` — add user_id to rows AND change onConflict

```dart
// BEFORE
final rows = streets
    .map(
      (street) => {
        'street_id': street.id,
        'city': street.city.isEmpty ? coverageCity : street.city,
        'drive_session_id': driveSessionId,
      },
    )
    .toList();

await supabase
    .from('street_coverage')
    .upsert(rows, onConflict: 'street_id');

// AFTER
final userId = supabase.auth.currentUser?.id;
final rows = streets
    .map(
      (street) => {
        'street_id': street.id,
        'city': street.city.isEmpty ? coverageCity : street.city,
        'drive_session_id': driveSessionId,
        'user_id': userId,
      },
    )
    .toList();

await supabase
    .from('street_coverage')
    .upsert(rows, onConflict: 'user_id,street_id');
```

### 2b. `addLead` — add user_id to the leads insert

In the `supabase.from('leads').insert({ ... })` map inside `addLead`, add:
```dart
'user_id': supabase.auth.currentUser?.id,
```

### 2c. `addParcelLead` — add user_id to the leads insert

Same addition inside the `supabase.from('leads').insert({ ... })` map in
`addParcelLead`.

### 2d. `saveDrivingPoint` — add user_id to BOTH inserts

`saveDrivingPoint` has a primary insert and a fallback insert (in the `catch`).
Add `'user_id': supabase.auth.currentUser?.id,` to **both** maps.

## Out of scope — do NOT change

- Reads (`loadLeads`, `loadStreetCoverage`, driving_points selects): RLS filters
  by user automatically once enabled. Do **not** add `.eq('user_id', ...)`.
- Lead scoring, the smart-score model, parcel rendering, house-number labels,
  the lead map filter, route tracking, or any UI.
- The auth layer (`AuthGate`, `LoginScreen`) — already done.
- Migration `0001` — leave it as-is; add `0002` only.

## Acceptance criteria

Run from the repo root; all must pass:

```
dart format --output=none --set-exit-if-changed .   # no changes
flutter analyze                                      # No issues found!
flutter test                                         # all pass (64 tests)
```

Plus:
- `supabase/migrations/0002_street_coverage_per_user.sql` exists.
- Only the four `lib/main.dart` write sites changed (+ the new migration file).
- The `street_coverage` upsert uses `onConflict: 'user_id,street_id'`.

Manual smoke (optional, needs the migrations applied): sign in, run **Simulate
Drive**, confirm street coverage still saves and the coverage % updates.

## Workflow

- Work on a branch named `codex/phase-2`.
- Match the existing code style (trailing commas; run `dart format`).
- Commit with a clear message, e.g. `Phase 2: per-user coverage + user_id stamping`.
- Do not push or merge — leave the branch for review.
```
