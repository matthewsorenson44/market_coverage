# Codex Implementation Checklist

Use this checklist before every code task in Market Coverage OS.

## Required Reading

Before coding, read:

1. `AGENTS.md`
2. `MASTER_PLAN.md`
3. `docs/master_plan.md`
4. `PROJECT_STATUS.md`
5. `CODEX_CHECKLIST.md`
6. `docs/project_journal.md`

## One-Task Rule

Every implementation session must have one single Task ID.

Do not work on later tasks.
Do not do unrelated refactors.
Do not quietly change product direction.

Use the ordered queue in `PROJECT_STATUS.md`. Each session takes the top task unless the user explicitly says otherwise. Completed tasks move to a short "Recently completed" list.

Do not start a new feature phase while more than 5 fixes sit at `fix pushed, awaiting user confirmation`. Prioritize DEV/FIELD tasks to burn down the backlog first.

## Before Editing

1. Identify the single Task ID being implemented.
2. Restate the task goal in 2-4 sentences.
3. List the exact files expected to change.
4. Confirm whether database changes are needed.
5. If database changes are needed, create a migration in `supabase/migrations` and explain any backfill assumptions.
6. Preserve existing behavior unless the task explicitly changes it.

## During Editing

1. Keep the change small and reviewable.
2. Prefer existing app patterns.
3. Do not rewrite large sections of `lib/main.dart`.
4. Put new features in new files under `lib/src/` or `lib/features/` where practical, not appended to `lib/main.dart`.
5. Extract existing code from `lib/main.dart` only when the current task already touches that code; never as a standalone rewrite.
6. Do not fake parcel, owner, street, source, or readiness data.
7. Do not disable RLS.
8. Do not put service role keys in Flutter.
9. Do not break Drive, Today, Leads, Areas, Settings, Quick Capture, photos, scoring, source tracking, route tracking, or street coverage unless the task explicitly changes that behavior.

## Validation

After coding, run:

1. `dart format .`
2. `flutter analyze`
3. `flutter test`

If any command fails, report the exact failure.

For docs-only changes, Flutter validation is optional. Say clearly that no app validation was run because no Dart code changed.

After DEV2 ships, every on-device bug report or fix confirmation should include the app build number and git commit hash shown in Settings. Journal confirmation entries must record that build hash.

## Status Updates

After each meaningful task, update:

1. `PROJECT_STATUS.md`
2. `docs/project_journal.md`

`PROJECT_STATUS.md` should include:

- Current phase
- Completed Task ID
- Files changed
- Migration added
- Test results
- Known issues
- Next recommended task

`docs/project_journal.md` should include:

- What changed
- What was validated
- Which bugs are still open
- Which bugs were fixed and are waiting for user confirmation
- Which bugs the user confirmed are fixed

## Commit Format

Use:

```text
<type>(<scope>): <TASK ID> <short description>
```

Examples:

```text
feat(inbox): T2 add inbox item model
feat(today): T1 add today command center
refactor(data): R1 add lead source model
fix(dedupe): D1 flag duplicate lead candidates
```

## Hard Rules

- One task per session.
- No broad rewrites.
- No hidden assumptions about future tasks.
- Keep code small, reviewable, and shippable.
- Explain exactly how to test.
