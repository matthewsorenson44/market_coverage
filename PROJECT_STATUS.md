# Market Coverage OS Project Status

## Current Phase

DEV1 complete: Mac/iPhone deploy loop documented and scripted so fresh builds can be pulled and tested without guessing commands.

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

DEV1: Mac deploy loop.

## Recently Completed

- DEV1: Added Mac testing docs and a deploy helper script for pulling the newest build and running it on iPhone.
- PLAN2: Roadmap and planning docs revised after July 2026 product/UX audit.
- FIX-COV1: Coverage integrity fix pushed in code; not yet confirmed on device because screenshots appear to be from a stale pre-July-1 build.
- T2: Today View shell with real tasks section.
- T1: Tasks data layer.
- R1: Lead source tracking, confirmed on device.

## Files Changed In Latest Status Update

- `docs/master_plan.md`
- `PROJECT_STATUS.md`
- `docs/project_journal.md`
- `docs/mac_testing.md`
- `scripts/mac_deploy.sh`
- `.gitattributes`

## Migration Added

None for DEV1.

## Test Results

- Docs/script-only change.
- No Dart code changed.
- `git diff --check` passed for the touched docs/script files.
- Bash syntax validation was not run because `bash` is not available in this Windows shell.
- Flutter validation was not run because no Dart code changed.

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

1. DEV2 - Build identity: show app version, build number, and git commit hash in Settings.
2. FIELD1 - Structured field-validation drive using the "Needs Real Driving Test" checklist.
3. FIX-GPS1 - Idle GPS drift filter.
4. FIX-SCORE1 - Property-scoring credibility guardrails.
5. STAT1 - Single source of truth for coverage numbers.
6. UX-LEADCARD1 - Lead list card hierarchy.
7. DN1 - Real Drive Next card on Today using existing mission-preview computation.
8. UX-AREA3 - Areas tab restructure.
9. MAP-AREA1 - Drive map area overlay upgrade.
10. MAP-TOGGLE1 - Independent map layer toggles for Streets and Parcels.
11. RR1 - Consolidate revisit reminders into tasks.
12. D1a - Capture-time dedupe flag.
13. C1 - CSV lead import.
14. T3-lite - Inbox surface inside Today.

## Next Recommended Task

DEV2: Build identity.

Start with a small Settings slice:

- Show app version, build number, and git commit hash in Settings.
- Make it easy to copy/report the build hash.
- Preserve existing Settings behavior.
- Do not touch Drive, Leads, Areas, or Today behavior.
