# Market Coverage OS Project Status

## Current Phase

Planning / V1 alignment.

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

Docs: V1 master plan alignment.

## Files Changed In Latest Status Update

- `docs/master_plan.md`
- `MASTER_PLAN.md`
- `CODEX_CHECKLIST.md`
- `PROJECT_STATUS.md`
- `docs/project_journal.md`
- `AGENTS.md`

## Migration Added

None.

## Test Results

Docs-only update.

No Dart code changed, so `dart format`, `flutter analyze`, and `flutter test` were not required for this status update.

## Known Issues

Use `docs/project_journal.md` as the detailed running list of open bugs, fixes awaiting user confirmation, and confirmed fixes.

Current high-priority open areas:

- Real-driving follow mode still needs field validation.
- GPS drift can draw route lines while idle.
- Mission and area analysis UX is still confusing.
- Map overlay visibility and toggles need continued cleanup.
- Lead deletion needs final user confirmation after the fixed-length list bug fix.
- Today and Inbox are V1 targets but do not exist yet.

## Next Recommended Task

T1: Today Queue + Tasks.

Start with a thin vertical slice:

- Add a `tasks` migration.
- Add a minimal Today command center shell.
- Show overdue tasks, due-today tasks, and new leads.
- Keep existing Drive, Leads, Areas, and Settings behavior intact.
