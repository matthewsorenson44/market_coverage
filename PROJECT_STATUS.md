# Market Coverage OS Project Status

## Current Phase

T1 Tasks Data Layer complete; ready for T2 Today View.

The current product direction is documented in `docs/master_plan.md`.

## Completed Foundation

- Phase 0 security/RLS: complete and verified.
- R1 lead source tracking: complete and verified.
- Lead photo uploads: fixed and confirmed.
- CSV export for skip tracing: fixed and confirmed.
- Drive OS foundation: substantially built.

## Current Shipped App State

The current shipped app still has 4 tabs:

1. Drive
2. Leads
3. Areas
4. Settings

The V1 target navigation is:

1. Today
2. Drive
3. Inbox
4. Leads
5. Markets

Today and Inbox do not exist yet.

## Most Recent Completed Task ID

T1: Tasks Data Layer.

## Files Changed In Latest Status Update

- `lib/main.dart`
- `test/lead_logic_test.dart`
- `supabase/migrations/0016_create_tasks.sql`
- `docs/master_plan.md`
- `PROJECT_STATUS.md`
- `docs/project_journal.md`

## Migration Added

- `supabase/migrations/0016_create_tasks.sql`

Manual SQL still needs to be run in Supabase before live task creation will work.

Backfill assumptions: none. The `tasks` table is new and starts empty.

## Test Results

- `dart format .`: passed
- `flutter analyze`: passed with no issues
- `flutter test`: passed with 125 tests

## Known Issues

Use `docs/project_journal.md` as the detailed running list of open bugs, fixes awaiting user confirmation, and confirmed fixes.

Current high-priority open areas:

- Real-driving follow mode still needs field validation.
- GPS drift can draw route lines while idle.
- Mission and area analysis UX is still confusing.
- Map overlay visibility and toggles need continued cleanup.
- Lead deletion needs final user confirmation after the fixed-length list bug fix.
- Today and Inbox are V1 targets but do not exist yet.
- T1 task UI depends on running `0016_create_tasks.sql` manually in Supabase.

## Next Recommended Task

T2: Today View.

Start with a thin vertical slice:

- Add the Today command center tab/shell.
- Read from the T1 `tasks` table.
- Show overdue tasks, due-today tasks, and new leads.
- Keep existing Drive, Leads, Areas, and Settings behavior intact.
