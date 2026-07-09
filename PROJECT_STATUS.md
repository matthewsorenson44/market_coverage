# Market Coverage OS Project Status

## Current Phase

PLAN3 complete: July 2026 redesign specs have been added to the roadmap for Today, Drive idle, status-colored map pins, and photo-first Quick Capture.

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

PLAN3: Add Today, Drive, pin, and capture screen specs.

## Recently Completed

- PLAN3: Added docs-only redesign specs for Today command center, Drive idle simplification, status-colored lead pins, and photo-first Quick Capture. DN1 was folded into UX-TODAY1.
- DEV2: Added copyable build identity to Settings and taught the Mac deploy script to inject the exact Git commit into the app.
- DEV1: Added Mac testing docs and a deploy helper script for pulling the newest build and running it on iPhone. User confirmed the deploy loop works after the Supabase project was resumed.
- PLAN2: Roadmap and planning docs revised after July 2026 product/UX audit.
- FIX-COV1: Coverage integrity fix pushed in code; not yet confirmed on device because screenshots appear to be from a stale pre-July-1 build.
- T2: Today View shell with real tasks section.
- T1: Tasks data layer.
- R1: Lead source tracking, confirmed on device.

## Files Changed In Latest Status Update

- `docs/master_plan.md`
- `PROJECT_STATUS.md`
- `docs/project_journal.md`

## Migration Added

None for PLAN3.

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

1. FIELD1 - Structured field-validation drive using the "Needs Real Driving Test" checklist.
2. FIX-GPS1 - Idle GPS drift filter.
3. FIX-SCORE1 - Property-scoring credibility guardrails.
4. STAT1 - Single source of truth for coverage numbers.
5. UX-LEADCARD1 - Lead list card hierarchy.
6. UX-TODAY1 - Today command center redesign, absorbing DN1 Drive Next.
7. UX-AREA3 - Areas tab restructure.
8. MAP-AREA1 - Drive map area overlay upgrade.
9. MAP-TOGGLE1 - Independent map layer toggles for Streets and Parcels.
10. MAP-PIN1 - Status-colored lead pins.
11. UX-CAPTURE1 - Photo-first Quick Capture.
12. UX-DRIVE1 - Drive idle simplification.
13. RR1 - Consolidate revisit reminders into tasks.
14. D1a - Capture-time dedupe flag.
15. C1 - CSV lead import.
16. T3-lite - Inbox surface inside Today.

Queue ordering rationale:

- MAP-PIN1 follows MAP-TOGGLE1 because the layers sheet becomes the home for the lead-status legend.
- UX-CAPTURE1 follows map pin clarity because capture speed is the next highest-payoff field workflow.
- UX-DRIVE1 follows the map/capture cleanup so the idle Drive redesign can reuse the cleaner layer and capture controls.

## Next Recommended Task

FIELD1: Structured field-validation drive.

Use the new Settings build identity for every confirmation or reopened bug:

- Pull the newest build on the Mac.
- Copy `Settings > Build Identity`.
- Test the real-driving checklist in `docs/project_journal.md`.
- Move confirmed fixes out of the awaiting-confirmation backlog.
