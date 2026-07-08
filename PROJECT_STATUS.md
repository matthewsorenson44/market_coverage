# Market Coverage OS Project Status

## Current Phase

DEV2 complete: Settings now shows app version, build number, Git commit, branch, and build time so device reports can be tied to an installed build.

The current product direction is documented in `docs/master_plan.md`.

## Completed Foundation

- Phase 0 security/RLS: complete and verified.
- R1 lead source tracking: complete and verified on device.
- Lead photo uploads: fixed and confirmed.
- CSV export for skip tracing: fixed and confirmed.
- T1 tasks data layer: complete.
- T2 Today View shell with real tasks section: complete.
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

DEV2: Build identity.

## Recently Completed

- DEV2: Added copyable build identity to Settings and taught the Mac deploy script to inject the exact Git commit into the app.
- DEV1: Added Mac testing docs and a deploy helper script for pulling the newest build and running it on iPhone. User confirmed the deploy loop works after the Supabase project was resumed.
- PLAN2: Roadmap and planning docs revised after July 2026 product/UX audit.
- FIX-COV1: Coverage integrity fix pushed in code; not yet confirmed on device because screenshots appear to be from a stale pre-July-1 build.
- T2: Today View shell with real tasks section.
- T1: Tasks data layer.
- R1: Lead source tracking, confirmed on device.

## Files Changed In Latest Status Update

- `lib/main.dart`
- `test/build_identity_test.dart`
- `scripts/mac_deploy.sh`
- `docs/mac_testing.md`
- `PROJECT_STATUS.md`
- `docs/project_journal.md`

## Migration Added

None for DEV2.

## Test Results

- `dart format .` passed with 40 files checked and 0 changed.
- `flutter analyze` passed with no issues.
- `flutter test` passed with 130 tests.

## Known Issues

Use `docs/project_journal.md` as the detailed running list of open bugs, fixes awaiting user confirmation, and confirmed fixes.

Current high-priority open areas:

- Real-driving follow mode still needs field validation.
- GPS drift can draw route lines while idle.
- Mission and area analysis UX is still confusing.
- Map overlay visibility and toggles need continued cleanup.
- Lead deletion needs final user confirmation after the fixed-length list bug fix.
- Coverage stat display is fixed in code but still needs real-device/field confirmation on a fresh build.
- Street count mismatch between Choose Market and Areas market card needs investigation.
- Mission preview and recap session estimates can disagree.
- Today now exists as a shell with a real tasks section.
- Drive Next is a placeholder and does not compute coverage recommendations yet.
- Inbox is a placeholder inside Today and the full Inbox flow is not implemented yet.
- Property scoring needs a credibility pass so commercial/non-SFR properties do not look like ordinary driving-for-dollars leads.

## Ordered Task Queue

Take the top task unless the user explicitly says otherwise.

1. FIELD1 - Structured field-validation drive using the "Needs Real Driving Test" checklist.
2. FIX-GPS1 - Idle GPS drift filter.
3. FIX-SCORE1 - Property-scoring credibility guardrails.
4. STAT1 - Single source of truth for coverage numbers.
5. UX-LEADCARD1 - Lead list card hierarchy.
6. DN1 - Real Drive Next card on Today using existing mission-preview computation.
7. UX-AREA3 - Areas tab restructure.
8. MAP-AREA1 - Drive map area overlay upgrade.
9. MAP-TOGGLE1 - Independent map layer toggles for Streets and Parcels.
10. RR1 - Consolidate revisit reminders into tasks.
11. D1a - Capture-time dedupe flag.
12. C1 - CSV lead import.
13. T3-lite - Inbox surface inside Today.

## Next Recommended Task

FIELD1: Structured field-validation drive.

Use the new Settings build identity for every confirmation or reopened bug:

- Pull the newest build on the Mac.
- Copy `Settings > Build Identity`.
- Test the real-driving checklist in `docs/project_journal.md`.
- Move confirmed fixes out of the awaiting-confirmation backlog.
