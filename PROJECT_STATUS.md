# Market Coverage OS Project Status

## Current Phase

PLAN2 complete: July 2026 product/UX audit incorporated into the master plan, project status, checklist, and journal.

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

PLAN2: Revise roadmap, add UX specs, and tighten plan process after July 2026 audit.

## Recently Completed

- PLAN2: Roadmap and planning docs revised after July 2026 product/UX audit.
- FIX-COV1: Coverage integrity fix pushed in code; not yet confirmed on device because screenshots appear to be from a stale pre-July-1 build.
- T2: Today View shell with real tasks section.
- T1: Tasks data layer.
- R1: Lead source tracking, confirmed on device.

## Files Changed In Latest Status Update

- `docs/master_plan.md`
- `PROJECT_STATUS.md`
- `docs/project_journal.md`
- `CODEX_CHECKLIST.md`

## Migration Added

None for PLAN2.

## Test Results

- Docs-only change.
- No Dart code changed.
- Flutter validation was not run.

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

1. DEV1 - Mac deploy loop: commit `scripts/mac_deploy.sh` and/or `docs/mac_testing.md` with exact copy-paste commands for the Mac.
2. DEV2 - Build identity: show app version, build number, and git commit hash in Settings.
3. FIELD1 - Structured field-validation drive using the "Needs Real Driving Test" checklist.
4. FIX-GPS1 - Idle GPS drift filter.
5. FIX-SCORE1 - Property-scoring credibility guardrails.
6. STAT1 - Single source of truth for coverage numbers.
7. UX-LEADCARD1 - Lead list card hierarchy.
8. DN1 - Real Drive Next card on Today using existing mission-preview computation.
9. UX-AREA3 - Areas tab restructure.
10. MAP-AREA1 - Drive map area overlay upgrade.
11. MAP-TOGGLE1 - Independent map layer toggles for Streets and Parcels.
12. RR1 - Consolidate revisit reminders into tasks.
13. D1a - Capture-time dedupe flag.
14. C1 - CSV lead import.
15. T3-lite - Inbox surface inside Today.

## Next Recommended Task

DEV1: Mac deploy loop.

Start with a tiny docs/script slice:

- Add exact Mac commands for the real repo path.
- Include `git pull`, `flutter pub get`, and the iPhone run command.
- Make it clear how to confirm the Mac is running the newest pushed build.
- Do not touch app behavior.
