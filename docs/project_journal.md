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

- iPhone Drive Mode follow-me can still appear to freeze or fail to follow smoothly.
- Some mission flows are confusing, especially when area analysis has not produced mission streets.
- Area analysis and market map loading can feel slow on iPhone.
- Mission completion and recap flow should stay simple and avoid stuck panels.
- Auth/account UX is basic; logout and multi-user testing need to stay visible.

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
