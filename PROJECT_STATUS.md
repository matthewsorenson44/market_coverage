# Market Coverage OS Project Status

## Current Phase

FIELD1 complete: a structured field-validation checklist now exists for real iPhone driving tests and build-hash-based confirmations.

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

FIELD1: Structured field-validation drive.

## Recently Completed

- FIELD1: Added `docs/field_validation.md`, a build-hash-based real-driving test runbook for follow mode, GPS drift, missions, coverage persistence, map layers, Quick Capture, and key regressions.
- PLAN3: Added docs-only redesign specs for Today command center, Drive idle simplification, status-colored lead pins, and photo-first Quick Capture. DN1 was folded into UX-TODAY1.
- DEV2: Added copyable build identity to Settings and taught the Mac deploy script to inject the exact Git commit into the app.
- DEV1: Added Mac testing docs and a deploy helper script for pulling the newest build and running it on iPhone. User confirmed the deploy loop works after the Supabase project was resumed.
- PLAN2: Roadmap and planning docs revised after July 2026 product/UX audit.
- FIX-COV1: Coverage integrity fix pushed in code; not yet confirmed on device because screenshots appear to be from a stale pre-July-1 build.
- T2: Today View shell with real tasks section.
- T1: Tasks data layer.
- R1: Lead source tracking, confirmed on device.

## Files Changed In Latest Status Update

- `docs/field_validation.md`
- `PROJECT_STATUS.md`
- `docs/project_journal.md`

## Migration Added

None for FIELD1.

## Test Results

Docs-only change. No Dart code changed, so Flutter validation was not run.

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

1. FIX-GPS1 - Idle GPS drift filter.
2. FIX-SCORE1 - Property-scoring credibility guardrails.
3. STAT1 - Single source of truth for coverage numbers.
4. UX-LEADCARD1 - Lead list card hierarchy.
5. UX-TODAY1 - Today command center redesign, absorbing DN1 Drive Next.
6. UX-AREA3 - Areas tab restructure.
7. MAP-AREA1 - Drive map area overlay upgrade.
8. MAP-TOGGLE1 - Independent map layer toggles for Streets and Parcels.
9. MAP-PIN1 - Status-colored lead pins.
10. UX-CAPTURE1 - Photo-first Quick Capture.
11. UX-DRIVE1 - Drive idle simplification.
12. RR1 - Consolidate revisit reminders into tasks.
13. D1a - Capture-time dedupe flag.
14. C1 - CSV lead import.
15. T3-lite - Inbox surface inside Today.

Queue ordering rationale:

- MAP-PIN1 follows MAP-TOGGLE1 because the layers sheet becomes the home for the lead-status legend.
- UX-CAPTURE1 follows map pin clarity because capture speed is the next highest-payoff field workflow.
- UX-DRIVE1 follows the map/capture cleanup so the idle Drive redesign can reuse the cleaner layer and capture controls.

## Next Recommended Task

FIX-GPS1: Idle GPS drift filter.

The FIELD1 checklist now lives in `docs/field_validation.md`. Use that checklist on the next real drive and send the completed FIELD1 report back with the Settings build identity.
