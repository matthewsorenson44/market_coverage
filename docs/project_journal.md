# Market Coverage OS Project Journal

## Product Vision

Apple Maps for driving-for-dollars, market coverage, and real estate wholesaler CRM.

Market Coverage OS should help a wholesaler see where they have driven, what streets and areas still need coverage, which properties look like opportunities, and what leads need follow-up.

## Main User Flow

1. User chooses an active market.
2. User creates or selects a Drive Area.
3. User analyzes the area to find streets and target properties.
4. User starts a Mission.
5. App tracks live GPS during the drive.
6. App marks streets as covered.
7. User adds leads while driving.
8. User adds photos, tags, notes, scores, and property details.
9. User completes the mission.
10. Dashboard and area views show coverage, leads, follow-ups, and pipeline progress.

## Current MVP Priority

Drive Mode reliability comes before advanced CRM features.

The app should feel dependable in the field before adding more automation:

- GPS should find and follow the user without freezing.
- Mission start and completion should be obvious.
- Quick Capture should add a lead without crashing.
- Street coverage should show useful, believable numbers.
- Lead photos should upload and display reliably.

## Current Product Areas

- Drive Mode with map, GPS, follow-me foundation, route tracking, and Quick Capture.
- Drive Areas and Missions.
- Street coverage intelligence.
- Parcel lookup and property preview.
- Lead list and lead details.
- Lead photos through Supabase Storage.
- Lead scoring, source, pipeline stage, reminders, ARV, repair cost, assignment fee, and MAO.
- Market catalog and readiness states.

## Current Known Issues To Watch

- Open: iPhone Drive Mode follow-me can still appear to freeze or fail to follow smoothly.
- Open: While sitting idle, the user marker can drift and draw a blue route line. Route tracking should avoid saving/displaying movement from GPS noise when stationary.
- Open: Some mission flows are confusing, especially when area analysis has not produced mission streets.
- Open: Area analysis state is unclear. Areas without street data show "No street data"; areas with street data show "Start Driving" and "Find Motivated Sellers" instead of making the analyze/ready state obvious.
- Open: Area analysis and market map loading can feel slow on iPhone.
- Open: Mission completion and recap flow should stay simple and avoid stuck panels.
- Open: "Find Motivated Sellers" is unclear and may appear to do nothing. It should either clearly explain/run the target-property analysis, be moved, or be removed from the mission-start path.
- Open: Mission coverage math can be misleading. Example to verify/fix: 1 of 2 streets should show 50%, not 0%.
- Open: Map overlays are too tied to selected areas. User wants separate toggles for showing all parcels and showing all streets, even when no area is selected.
- Open: Lead Details page can overflow on iPhone.
- Open: Auth/account UX is basic; logout and multi-user testing need to stay visible.
- Fix pushed, awaiting user confirmation: Drive map style switching should follow dark/light theme by default, with a manual style picker for Auto, Dark, Standard, Minimal, and Satellite.
- Fix pushed, awaiting user confirmation: Property Preview should no longer overlap the iPhone status bar and should have a sticky top-right X close button.
- Fix pushed, awaiting user confirmation: Lead Details should have a pinned top-right X close button.
- Fix pushed, awaiting user confirmation: Mission recap dark-mode cards/text should be readable.
- Fix pushed, awaiting user confirmation: Quick Capture red-screen crash when adding a lead from the orange lightning button while an area is selected.
- Needs confirmation: Quick Capture should close cleanly after saving.

## Needs Real Driving Test

- Follow mode actually follows while driving, not just says "Following."
- User marker updates smoothly while moving.
- App does not freeze when GPS icon changes from dot to arrow.
- Area stats show streets driven / total streets correctly during real driving.
- Area stats show miles covered / total miles correctly during real driving.
- Covered streets turn green after driving.
- Street coverage persists after app restart after a real drive.

## Needs Retest Or Clarification

- Owasso streets show correctly.
- Tulsa streets show where imported.
- Undriven streets stay red.
- Analyze Area no longer reopens weirdly, but current empty/ready states are confusing and need UX cleanup.

## Fixed And Confirmed By User

- Lead photo uploads work after Supabase Storage RLS policy fixes.
- Lead photo display after upload works.
- Mission manual test passed.
- Coverage manual test passed.
- Area Name dialog TextField crash was fixed and covered by tests.

## Journal Maintenance Rules

Codex should use this journal as the running memory for the project.

At the start of each coding task:

1. Read `AGENTS.md`.
2. Read this file.
3. Use the current MVP priority and known issues to avoid drifting into unrelated work.

At the end of each meaningful task or bug-fix session:

1. Add a new entry to `Recent Work Log`.
2. Update `Current Known Issues To Watch`.
3. If a bug fix was pushed but the user has not tested it yet, mark it as `Fix pushed, awaiting user confirmation`.
4. When the user says a bug is fixed, remove it from `Current Known Issues To Watch`.
5. Move confirmed fixes to `Fixed And Confirmed By User`.
6. Keep old confirmed fixes brief so the journal stays useful.

Bug status meanings:

- `Open`: Reported or observed, not fixed yet.
- `In progress`: Codex is actively working on it.
- `Fix pushed, awaiting user confirmation`: Code was changed and validated, but the user has not tested on the real device yet.
- `Confirmed fixed`: User tested and said it works.

## Recent Work Log

### 2026-06-25

- Added `AGENTS.md` and this project journal so future Codex work starts with product context.
- Fixed Quick Capture TextField lifecycle crash path in `lib/main.dart`.
- Quick Capture fix details: owns a FocusNode for the quick note field, unfocuses before save/close, delays TextEditingController/FocusNode disposal until after the bottom sheet close animation, guards async lookup/save callbacks while closing, and disables save buttons during close.
- Validation for Quick Capture fix: `dart format .`, `flutter analyze`, and `flutter test` passed with 111 tests.
- Status: Quick Capture fix is pushed and awaiting user confirmation on iPhone.
- User began a real iPhone bug sweep and reported current open/deferred items.
- Deferred until a real drive: follow-me behavior, smooth moving marker updates, GPS icon arrow freeze, street/mile stats while moving, covered streets turning green, and persistence after driving.
- Newly captured open UX/data issues: idle GPS drift can draw a route line, "Find Motivated Sellers" is unclear, mission coverage math may show 0% for partial coverage, parcel/street layers need independent toggles, Lead Details can overflow on iPhone, and area analyze/ready states need clearer wording.
- Built Step 1 of the Market Coverage OS 2.0 design system: color, typography, spacing, shadow, animation tokens, app theme, debug-only design-system gallery, and barrel export.
- Wired the existing `MaterialApp` to `AppTheme.lightTheme()`, `AppTheme.darkTheme()`, and `ThemeMode.system`.
- Added `google_fonts` for Inter and JetBrains Mono typography.
- Validation for design-system Step 1: `dart format lib/design_system/ lib/design_system.dart`, `flutter analyze`, and `flutter test` passed with 111 tests.
- Added Drive map style switching in `lib/main.dart`: Auto follows theme, Dark uses Carto Dark Matter, Standard uses Carto Voyager, Minimal uses Carto Light, and Satellite uses Esri World Imagery.
- Added a small layers button on the Drive map to choose the map style and persist the choice in `SharedPreferences`.
- Fixed Property Preview readability/overlap by adding a solid sticky header with a top-right X close button and scrollable content underneath.
- Changed Lead Details to use a pinned top-right X close button.
- Improved mission recap dark-mode contrast for cards, metric text, and summary rows.
- Validation for map style/UI fix: `dart format lib/main.dart`, `flutter analyze`, and `flutter test` passed with 111 tests.

### 2026-06-24

- Lead photo uploads were fixed through Supabase Storage RLS policy work.
- User confirmed photo upload works.
- Drive Mode GPS and mission flow received fixes, but user later reported follow-me freezing and mission confusion, so those remain open.

## Engineering Rules

- Make small, safe changes.
- Preserve existing Supabase, map, GPS, route tracking, lead, photo, score, source, pipeline, and parcel behavior.
- Do not fake parcel lines, fake streets, fake addresses, or fake readiness.
- Use real imported data for street and parcel features.
- Run `dart format .`, `flutter analyze`, and `flutter test` after code changes.
- Explain exactly what changed and exactly how to test it.

## Prompt Reminder

For future work, start with:

> Read `AGENTS.md` and `docs/project_journal.md` first before making changes.
