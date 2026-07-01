# Market Coverage OS Project Status

## Current Phase

T2 Today View complete; ready for T3 Inbox Surface Inside Today.

The current product direction is documented in `docs/master_plan.md`.

## Completed Foundation

- Phase 0 security/RLS: complete and verified.
- R1 lead source tracking: complete and verified.
- Lead photo uploads: fixed and confirmed.
- CSV export for skip tracing: fixed and confirmed.
- Drive OS foundation: substantially built.

## Current Shipped App State

The current shipped app has 5 tabs:

1. Today
2. Drive
3. Leads
4. Areas
5. Settings

The V1 target navigation is:

1. Today
2. Drive
3. Inbox
4. Leads
5. Markets

Inbox and Markets are V1 target tabs and do not exist yet. Areas remains the current bridge toward Markets.

## Most Recent Completed Task ID

T2: Today View.

## Files Changed In Latest Status Update

- `lib/main.dart`
- `test/lead_logic_test.dart`
- `PROJECT_STATUS.md`
- `docs/project_journal.md`

## Migration Added

None for T2.

T2 uses the existing `tasks` table from T1.

## Test Results

- `dart format .`: passed
- `flutter analyze`: passed with no issues
- `flutter test`: passed with 126 tests

## Known Issues

Use `docs/project_journal.md` as the detailed running list of open bugs, fixes awaiting user confirmation, and confirmed fixes.

Current high-priority open areas:

- Real-driving follow mode still needs field validation.
- GPS drift can draw route lines while idle.
- Mission and area analysis UX is still confusing.
- Map overlay visibility and toggles need continued cleanup.
- Lead deletion needs final user confirmation after the fixed-length list bug fix.
- Today now exists as a shell with a real tasks section.
- Drive Next is a placeholder and does not compute coverage recommendations yet.
- Inbox is a placeholder inside Today and the full Inbox flow is not implemented yet.

## Next Recommended Task

T3: Inbox Surface Inside Today.

Start with a thin vertical slice:

- Add `inbox_items`.
- Surface unreviewed inbound items inside Today.
- Let the user review or resolve an inbox item.
- Keep existing Today, Drive, Leads, Areas, and Settings behavior intact.
