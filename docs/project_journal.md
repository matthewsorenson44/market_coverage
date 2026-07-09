# Market Coverage OS Project Journal

## Product Vision

Source of truth for the larger product plan: `docs/master_plan.md`.

Apple Maps for driving-for-dollars, market coverage, and real estate wholesaler CRM.

Market Coverage OS should help a wholesaler see where they have driven, what streets and areas still need coverage, which properties look like opportunities, and what leads need follow-up.

MVP strategy update: owner/property ownership data is not required for MVP. The core app should be built around nationwide driving-for-dollars lead capture: market/city selection, street coverage, Drive Areas, missions, Quick Capture, GPS/address capture, photos, tags, notes, lead scoring, CSV export for skip tracing, and CSV import/enrichment later. Parcel boundaries and owner data are optional by market and must never block lead capture.

Master plan update: the app should become a unified seller-lead command center, not only a field capture app. Driving for Dollars brings users in; Lead Funnel OS and Today Queue keep them organized. V1 target navigation is five tabs: Today, Drive, Inbox, Leads, and Markets. The current shipped app now has five tabs: Today, Drive, Leads, Areas, and Settings. Inbox and Markets do not exist yet as first-class tabs; Areas remains the bridge toward Markets.

## Main User Flow

1. User opens Today and sees the seller leads, follow-ups, appointments, and driving work that need attention now.
2. User chooses an active market.
3. User creates or selects a Drive Area.
4. User analyzes the area to find streets and target properties where data exists.
5. User starts a Mission.
6. App tracks live GPS during the drive.
7. App marks streets as covered.
8. User adds leads while driving with GPS/address capture.
9. User adds photos, tags, notes, scores, and property details.
10. Leads from field capture, CSV imports, website/webhooks, ads, phone/SMS, email, direct mail, and referrals flow into one lead funnel.
11. User completes the mission.
12. Today, Leads, and Markets show coverage, new leads, follow-ups, appointments, source attribution, and pipeline progress.

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
- Optional parcel lookup and property preview where market data exists.
- Lead list and lead details.
- Lead photos through Supabase Storage.
- Lead scoring, source, pipeline stage, reminders, ARV, repair cost, assignment fee, and MAO.
- Market catalog and readiness states.
- Lead funnel direction: source attribution, tasks, Today Queue, inbox items, inbound events, calendar items, and attribution links should be added only as thin vertical slices with working UI.
- T1 task data layer is implemented and user-confirmed: Lead Details can create, list, and complete lead-attached tasks.
- T2 Today View is implemented as the first tab: it loads open overdue/due-today tasks from Supabase, lets the user complete tasks inline, opens the attached lead, and includes placeholder widgets for Drive Next and Inbox.
- R1 lead source tracking is confirmed on device: the full 13-value source dropdown uses friendly labels and lead cards show colored source chips.
- DEV2 build identity is implemented: Settings shows the app version, build number, Git commit, branch, and build time, and the Mac deploy script injects those values into iPhone builds.
- DEV1a Mac deploy hardening is implemented: the deploy helper fetches GitHub, refuses local Mac-only work, resets to the fetched branch only when safe, and prints the updated commit hash for comparison with Settings > Build Identity.
- PLAN3 redesign specs are documented: Today command center, Drive idle simplification, status-colored lead pins, and photo-first Quick Capture.
- FIELD1 field-validation runbook exists at `docs/field_validation.md` for build-hash-based iPhone driving tests.

## Current Known Issues To Watch

- Open: iPhone Drive Mode follow-me can still appear to freeze or fail to follow smoothly.
- Open: While sitting idle, the user marker can drift and draw a blue route line. Route tracking should avoid saving/displaying movement from GPS noise when stationary.
- Open: Some mission flows are confusing, especially when area analysis has not produced mission streets.
- Open: Area analysis state is unclear. Areas without street data show "No street data"; areas with street data show "Start Driving" and "Find Motivated Sellers" instead of making the analyze/ready state obvious.
- Open: Area analysis and market map loading can feel slow on iPhone.
- Open: Mission completion and recap flow should stay simple and avoid stuck panels.
- Open: "Find Motivated Sellers" is unclear and may appear to do nothing. It should either clearly explain/run the target-property analysis, be moved, or be removed from the mission-start path.
- Open: Map overlays are too tied to selected areas. User wants separate toggles for showing all parcels and showing all streets, even when no area is selected.
- Open: Lead Details page can overflow on iPhone.
- Open: Auth/account UX is basic; logout and multi-user testing need to stay visible.
- Open: Property scoring needs a credibility pass so obvious commercial/non-SFR properties do not show like normal driving-for-dollars targets.
- Open: Street count mismatch between Choose Market showing 1000 and Areas market card showing 3323 for the same market.
- Open: Mission session estimates can be inconsistent between preview, such as about 3 sessions, and recap, such as 5.
- Open: Duplicate area names are possible, such as "ow" twice; areas can also be named after the wrong city, such as "tulsa" inside Owasso.
- Open: Start Mission can appear enabled on areas with no street data.
- Open: County parcel data can be dumped into lead Notes as free text instead of structured fields.
- Open: Leads header hero and stat tiles push actual leads below the fold; export affordances can feel duplicated.
- Open: Property Preview can show contradictory "New Lead" chip next to "Already a lead" text.
- Open: Score 0 renders in a green badge, which reads as positive.
- Open: House-number labels clutter the map at mid-zoom; needs tighter zoom threshold.
- Open: Quick Capture FAB can overlap the Plan panel corner on Drive.
- Open: Design Gallery button is too prominent in Settings and should be debug-gated.
- Needs confirmation: Today tab should show overdue/due-today tasks, open the attached lead when tapped, and remove a task when completed inline.
- Fix pushed, awaiting user confirmation: Coverage stat display now uses street-count percent for "Streets driven" labels, separates street miles from route miles, and avoids showing route miles as covered street miles. July 2026 screenshots still showing "Streets driven: 9 of 158 (0%)" appear to be from a stale installed build that predates the July 1 fix.
- Fix pushed, awaiting user confirmation: Drive map style switching should follow dark/light theme by default, with a manual style picker for Auto, Dark, Minimal, and Satellite. The old Standard option now falls back to Auto.
- Fix pushed, awaiting user confirmation: Parcel boundary lines should stay visible during active missions instead of disappearing while tracking/following.
- Fix pushed, awaiting user confirmation: Parcel boundary colors should contrast better on Satellite, Dark, and light map styles.
- Fix pushed, awaiting user confirmation: Leads can be deleted from the Leads tab and from Lead Details with a confirmation prompt. User reported the first live test was still blocked after `0012_lead_delete_policy.sql`, so the app now uses secure RPC migration `0013_delete_lead_rpc.sql` and cleans related lead photo rows/storage before deleting. Latest device error showed local state cleanup crashing with "Cannot remove from a fixed-length list"; the app now replaces lead lists immutably after delete instead of mutating them in place.
- Fix pushed, awaiting user confirmation: Property Preview should no longer overlap the iPhone status bar and should have a sticky top-right X close button.
- Fix pushed, awaiting user confirmation: Lead Details should have a pinned top-right X close button.
- Fix pushed, awaiting user confirmation: Mission recap dark-mode cards/text should be readable.
- Fix pushed, awaiting user confirmation: Quick Capture red-screen crash when adding a lead from the orange lightning button while an area is selected.
- Fix pushed, awaiting user confirmation: Drive no longer shows the hard-to-read location status strip over the map.
- Fix pushed, awaiting user confirmation: The Find Me/Following button is smaller and color-coded by state.
- Fix pushed, awaiting user confirmation: The mission next-road pill and progress pill should be readable in dark mode.
- Fix pushed, awaiting user confirmation: Map style picker should open as a readable solid bottom sheet.
- Fix pushed, awaiting user confirmation: Business tab has been removed from bottom navigation, and account/log out controls are in Settings.
- Fix pushed, awaiting user confirmation: Areas list cards should have readable stats/text in dark mode.
- Fix pushed, awaiting user confirmation: Property Preview now puts "What did you see?" and Add Lead above the property information.
- Fix pushed, awaiting user confirmation: Drive tab visual pass now uses design-system cards, buttons, chips, typography, and HUD treatments for planning, mission preview, active mission controls, Quick Capture, and first-run empty states.
- Fix pushed, awaiting user confirmation: Market readiness and lead capture no longer require owner/property ownership data. Missing owner data now tells users to export the lead list for skip tracing instead of implying the lead is incomplete.
- Fix pushed, awaiting user confirmation: Areas coverage stats should be readable in dark mode without changing light mode.
- Fix pushed, awaiting user confirmation: Parcel boundaries and parcel/lead markers should appear sooner and with stronger contrast on Satellite, Dark, and Minimal map styles, including during active missions.
- Fix pushed, awaiting user confirmation: Tapping a house with no parcel data now opens a fallback capture sheet instead of dead-ending at "No parcel found."
- Fix pushed, awaiting user confirmation: GPS-only Add Lead capture now tries to reverse-geocode the saved coordinates into a street address before saving, while still allowing GPS-only capture if the lookup fails.
- Fix pushed, awaiting user confirmation: Leads tab now has a skip-tracing CSV import flow that matches by `lead_id`, falls back to address, previews changes before writing, fills blank contact fields only, reports unmatched rows, queues failed enrichment updates for retry, and shows imported contact info in Lead Details.
- Needs confirmation: Quick Capture should close cleanly after saving.

## Needs Real Driving Test

Use `docs/field_validation.md` for the structured test run. Every report should include the Settings build identity.

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
- Skip-tracing CSV export works after readability fixes.
- T1 Lead Details tasks work after the user manually pushed/pulled and tested the feature.
- R1 lead source tracking is confirmed on device: 13-value source dropdown, friendly labels, and colored source chips on lead cards work.
- DEV1 Mac/iPhone deploy loop works after the user resumed the paused Supabase project and reran the app.
- DEV2 Build Identity works on Mac/iPhone: Settings shows build info and Copy Build Info copies it.

## Journal Maintenance Rules

Codex should use this journal as the running memory for the project.

At the start of each coding task:

1. Read `AGENTS.md`.
2. Read `MASTER_PLAN.md`.
3. Read `docs/master_plan.md`.
4. Read `PROJECT_STATUS.md`.
5. Read `CODEX_CHECKLIST.md`.
6. Read this file.
7. Use the current MVP priority and known issues to avoid drifting into unrelated work.

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

### 2026-07-08

- Implemented DEV1a Mac deploy hardening as a docs/script-only task.
- Updated `scripts/mac_deploy.sh` so the Mac deploy mirror uses `git fetch origin`, detects uncommitted/untracked files and local commits not on `origin/<branch>`, prints a loud warning, and aborts instead of overwriting local Mac work.
- Replaced the safe update path with `git reset --hard origin/<current branch>` only when the Mac mirror has no local work to keep.
- Added the updated short commit hash to the script output so testers can compare the terminal output to `Settings > Build Identity`.
- Updated `docs/mac_testing.md` with the new fetch/reset flow, the deploy-only mirror rule, and recovery guidance when the script stops.
- Validation: `git diff --check` passed for the touched files. Bash syntax validation was not run because `bash` is not available in this Windows shell. No Dart code changed and Flutter validation was not run.

- Implemented FIELD1 as a docs-only field-validation runbook.
- Added `docs/field_validation.md` with a structured real-driving checklist covering startup/location, mission start, live tracking, Quick Capture, mission completion, coverage persistence, map-layer visibility, and quick non-driving regressions.
- The runbook requires `Settings > Build Identity` to be copied into each report so confirmations and reopened bugs can be tied to an installed build.
- Updated project status so the next recommended task is `FIX-GPS1` idle GPS drift.
- Validation: docs-only change. No Dart code changed and Flutter validation was not run.

- Implemented PLAN3 as a docs-only planning update.
- Added competitive design benchmarks to the master plan: match category leaders on speed-to-action while protecting Market Coverage OS differentiators in street-level coverage, missions/areas, honest no-owner-data operation, and deal math.
- Folded the former DN1 Drive Next slice into `UX-TODAY1`, which now specifies the Today command center: Drive Next hero, Needs Attention tasks, New Leads Today, and Week Stats.
- Added planned slices for `MAP-PIN1` status-colored lead pins, `UX-CAPTURE1` photo-first Quick Capture, and `UX-DRIVE1` Drive idle simplification.
- Updated the ordered queue and status docs so future sessions follow the new order.
- Validation: docs-only change. No Dart code changed and Flutter validation was not run.

- Implemented DEV2 Build Identity.
- Added app build constants sourced from `--dart-define` and a Settings `Build Identity` section showing version, build number, Git commit, branch, and build time.
- Added a `Copy Build Info` button so future iPhone bug reports and fix confirmations can include the exact installed build.
- Updated `scripts/mac_deploy.sh` to read `pubspec.yaml`, compute the current Git commit/branch/build time after pull, print the build identity, and pass it into `flutter run`.
- Updated `docs/mac_testing.md` so Mac/iPhone testing uses `Settings > Build Identity` for reporting.
- Added a focused unit test for build-hash shortening.
- User confirmed DEV1 works after the paused Supabase project was resumed and the app loaded normally.
- Validation for DEV2: `dart format .`, `flutter analyze`, and `flutter test` passed with 130 tests.
- Next recommended task: FIELD1 structured real-driving validation using the build hash from Settings.

### 2026-07-07

- Implemented DEV1 Mac Deploy Loop as a docs/script-only task.
- Added `docs/mac_testing.md` with copy-paste Mac commands for `git pull --ff-only`, `flutter pub get`, `flutter devices`, and running the app on iPhone.
- Added `scripts/mac_deploy.sh`, a Mac helper script that refuses to pull over local changes, prints the before/after Git commit, installs Flutter packages, shows devices, and runs the app in release mode by default.
- Added `.gitattributes` so shell scripts keep LF line endings and remain runnable on macOS.
- Updated `PROJECT_STATUS.md` to mark DEV1 complete and set DEV2 Build Identity as the next recommended task.
- Validation: `git diff --check` passed for the touched docs/script files. Bash syntax validation was not run because `bash` is not available in this Windows shell. No Dart code changed and Flutter validation was not run.

### 2026-07-06

- Implemented PLAN2 as a docs-only planning update after the July 2026 product/UX audit.
- Updated `docs/master_plan.md` to reflect the current shipped 5-tab app state, the confirmed `created_at` / `updated_at` timestamp convention, and R1 source tracking as confirmed on device.
- Split V1 into a 1.0 Beta cut line and a 1.0 App Store cut line. Webhook intake, attribution links, and calendar items moved to 1.0.x / 1.1 instead of blocking beta.
- Added the ordered near-term task queue: DEV1, DEV2, FIELD1, FIX-GPS1, FIX-SCORE1, STAT1, UX-LEADCARD1, DN1, UX-AREA3, MAP-AREA1, MAP-TOGGLE1, RR1, D1a, C1, and T3-lite.
- Added planned UX specs for UX-AREA3 and MAP-AREA1, plus interface principles for progressive disclosure, one primary action, meaningful stats, Lead Details structure, and debug-gating the Design Gallery.
- Updated `PROJECT_STATUS.md` so the next recommended task is DEV1 Mac deploy loop.
- Updated `CODEX_CHECKLIST.md` with the validation backlog gate, build-hash confirmation rule, new-file guidance, and ordered-queue discipline.
- Added July 2026 audit issues to the open bug list, including street-count mismatch, inconsistent mission estimates, duplicate/misnamed areas, Start Mission gating, county parcel notes, lead-list hierarchy, score 0 styling, map label clutter, Quick Capture overlap, and Design Gallery prominence.
- Validation: docs-only change. No Dart code changed and Flutter validation was not run.

### 2026-07-01

- Implemented FIX-COV1 Coverage integrity after reviewing the screenshot-based audit recommendation that coverage is the product moat.
- Updated coverage stat display so "Streets driven" uses street-count math; examples like 9 of 158 now show a nonzero street percentage instead of a mileage-weighted 0%.
- Updated area progress bars to match street-count progress instead of mileage-weighted coverage when the label is about streets.
- Updated Drive coverage statistics to separate street coverage miles from route miles. Route miles now stay in the diagnostic line and are still used for leads-per-mile.
- Added a safe double-percent helper and regression coverage for empty/over-complete mileage totals.
- Validation for FIX-COV1: `dart format .`, `flutter analyze`, and `flutter test` passed with 127 tests.
- Status: awaiting user confirmation on iPhone/field data that area, Drive, mission, and recap coverage numbers now feel believable.
- Next recommended follow-up: property-type-aware scoring/leadability guardrails so commercial properties do not look like ordinary driving-for-dollars targets.

### 2026-06-30

- Implemented T2 Today View.
- Added Today as the first app tab while preserving the current Drive, Leads, Areas, and Settings tabs after it.
- Added a real Needs Attention section that loads open overdue and due-today tasks from the T1 `tasks` table for the current user.
- Added inline task completion from Today, which marks tasks `done`, sets `completed_at`, and removes them from the attention list.
- Added task tap behavior from Today to open the attached Lead Details screen.
- Added separate placeholder widgets for Drive Next and Inbox so later T3/Drive-intelligence slices can fill them without redesigning Today.
- Added a focused unit test for overdue/due-today task filtering.
- Validation for T2 Today View: `dart format .`, `flutter analyze`, and `flutter test` passed with 126 tests.

- Implemented T1 Tasks Data Layer.
- Confirmed the app/database timestamp convention is `created_at` and `updated_at`, so the new `tasks` table follows that convention.
- Added manual Supabase migration `0016_create_tasks.sql` for the new user-scoped `tasks` table with `open`/`done` status, optional due date, completed timestamp, RLS policies, indexes, and an `updated_at` trigger.
- Added the `LeadTask` Dart model, task status helpers, task sorting, and focused unit tests.
- Added minimal Lead Details task UI: create a lead task, view tasks for the lead, and mark a task complete. This does not build the Today tab.
- Updated project status to mark T1 complete and recommend T2 Today View next.
- Validation: `dart format .`, `flutter analyze`, and `flutter test` passed with 125 tests.
- Saved the rewritten V1 product direction into `docs/master_plan.md`.
- Added root `MASTER_PLAN.md` as a pointer because future prompts may reference that filename directly.
- Added `CODEX_CHECKLIST.md` with the one-task-per-session implementation checklist.
- Added `PROJECT_STATUS.md` with current phase, completed foundations, current shipped tab state, V1 target navigation, known issues, and next recommended task.
- Updated `AGENTS.md` so future coding work starts by reading the master plan, project status, checklist, and journal.
- Updated this journal so future coding sessions read the master plan, project status, checklist, and journal before making code changes.
- Validation: docs-only update. No Dart code changed, so Flutter validation was not run.

### 2026-06-29

- Fixed the latest lead delete failure reported from iPhone. The Supabase delete path could complete, then the app crashed while removing the deleted lead from a fixed-length local list.
- Updated both root lead state and Drive Mode lead state to replace the lead list with a fresh filtered list after deletion instead of calling `removeWhere` on the existing list.
- Status: awaiting user confirmation from both delete entry points: Leads tab trash icon and Lead Details trash icon.
- Added the data-layer piece of canonical lead source tracking. `Lead.source` now normalizes to `driving`, `manual`, `referral`, `facebook`, `website`, `csv_import`, or `other`; Quick Capture and drive/map-created leads write `driving`; manual Add Lead defaults to `manual`.
- Added manual-only Supabase migration `0014_lead_source_tracking.sql` to add/backfill/constrain `public.leads.source`. The migration has not been run by Codex and still needs to be run manually in Supabase before relying on the database constraint.
- Validation for lead source data layer: `dart format lib/main.dart` and `flutter analyze` passed.
- Added colored source chips to Leads tab cards using `AppBadgeSize.small`, with source colors stored in `AppColors` and display labels mapped from canonical source values.
- Validation for source chip UI: `dart format lib/main.dart lib/design_system/tokens/app_colors.dart` and `flutter analyze` passed.
- Fixed the follow-up source UI bug after device testing showed the previous source work was not visible/complete in-app. The app-side source taxonomy now matches the 13 allowed database values, old source labels normalize into safe canonical values, source dropdowns display readable labels, and the reusable design-system `LeadCard` also renders the source badge.

### 2026-06-28

- Added `docs/master_plan.md` as the source-of-truth master plan for Market Coverage OS.
- Updated the journal to align with the master plan: four-tab V1 navigation, Today Queue, unified lead funnel, source attribution, additive-only development, security gates, and no fake owner/parcel data.
- Marked the older redesign plan as historical where it conflicts with the new four-tab master plan.
- Validation for master plan update: docs-only change, so Flutter validation was not run.
- Built Prompt B2 skip-tracing CSV import in `lib/main.dart`.
- Added `owner_phone`, `owner_phone_2`, `owner_email`, `skip_traced`, and `skip_traced_at` handling to the `Lead` model. The required Supabase SQL still needs to be run before live import testing.
- Added a Leads tab import icon using `file_picker` to select `.csv` files and the existing `csv` package to parse quoted CSV correctly.
- Added case-insensitive/tolerant CSV header matching for `lead_id`, `property_address`/`address`, `owner_name`/`owner`, `owner_phone`/`phone`/`phone_1`, `owner_phone_2`/`phone_2`, and `owner_email`/`email`.
- Added a preview sheet before import writes: matched rows to enrich, unmatched rows with expandable details, and leads gaining a first phone number.
- Import merge rules fill blanks only and never overwrite notes, scores, tags, stage, source, existing owner/contact values, or any field-captured data.
- Added a small offline retry queue for failed lead enrichment updates and flushes it on app load/connectivity recovery.
- Added a Lead Details Contact section showing imported owner/phone/email data or the right skip-tracing empty state.
- Added unit tests for lead-id matching, address fallback, unmatched rows, missing matcher-column error, blank-cell no-op behavior, and no-overwrite behavior.
- Added `file_picker` and refreshed generated platform registration through `flutter pub get`.
- Validation for skip-tracing import: `dart format .`, `flutter analyze`, and `flutter test` passed with 118 tests.

### 2026-06-27

- Applied the Drive tab design-system Step 4 visual pass in `lib/main.dart`.
- Updated Drive map HUD elements, first-run empty state, Plan Today's Drive panel, mission planning bottom sheet, mission preview content, active mission pills, mission detail sheet, Quick Capture FAB, and Quick Capture bottom sheet styling to use the existing design-system tokens/components where safe.
- Preserved the existing Drive business logic: GPS/follow state, route tracking, mission lifecycle, Supabase saves, parcel lookup, lead creation, coverage writing, photos, scoring, CRM, ARV/MAO, and map data loading were not intentionally changed.
- Component caveat: the mission preview still uses a custom `AppCard` composition instead of the domain `MissionCard` because it is built from transient planning estimates, not a saved `Mission` model.
- Validation for Drive tab design pass: `dart format lib/main.dart`, `flutter analyze`, and `flutter test` passed with 111 tests.
- Status: awaiting user confirmation on iPhone for visual clarity, button placement, and bottom-sheet behavior.
- Updated the parcel/owner MVP strategy: street data now drives market readiness and mission eligibility, while parcel preview, target property maps, and owner enrichment are labeled optional.
- Added consistent missing-owner copy: "Owner data not available. Export this lead list for skip tracing."
- Property Preview, Quick Capture, Lead Details, market data layers, and market readiness now support driving-for-dollars capture without requiring owner names.
- Validation for owner/parcel strategy update: `dart format lib/main.dart`, `flutter analyze`, and `flutter test` passed with 111 tests.
- Improved dark-mode Areas coverage readability by making coverage stat text detect dark theme automatically while leaving light-mode colors unchanged.
- Lowered parcel/house-number zoom thresholds, strengthened parcel boundary contrast by map style, made parcel dots easier to distinguish, and allowed parcel layers to remain visible during tracking/follow mode.
- Added a no-parcel-data fallback bottom sheet from Drive map taps with an `Add Lead Here` action so missing parcel/owner data does not block capture.
- Validation for visibility/fallback fixes: `dart format lib/main.dart`, `flutter analyze`, and `flutter test` passed with 111 tests.
- Added best-effort reverse geocoding for GPS-only Add Lead capture. When a lead is started from a map/GPS point with no parcel data, the Add Lead screen now looks up the nearest address, prefills the Property Address field when available, and clearly says GPS will still be saved if address lookup fails.
- Validation for GPS-to-address lead capture: `dart format lib/main.dart`, `flutter analyze`, and `flutter test` passed with 111 tests.
- Added Prompt B1 skip-tracing CSV export from the Leads tab. The export sheet lets users choose available lead columns, locks `lead_id` as the first column for future import matching, exports only visible/filtered leads, and uses native share/download via `share_plus`.
- Added `csv` for safe CSV generation and updated the older pure CSV helper to use package-based escaping instead of manual field escaping.
- Added unit tests for selected-column export, semicolon-separated condition tags, and blank missing values.
- Validation for CSV export: `dart format .`, `flutter analyze`, and `flutter test` passed with 114 tests.
- Fixed skip-tracing export sheet readability. The sheet now uses an opaque theme-aware Material panel, explicit dark/light text and surface colors, a solid checklist card, and a darker scrim so the Leads page no longer bleeds through behind the export controls.
- Validation for export sheet readability: `dart format lib/main.dart`, `flutter analyze`, and `flutter test` passed with 114 tests.
- Reworked lead deletion after the user confirmed it still did not work on-device. The app now cleans lead photo storage and optional `lead_photos` rows before deleting, calls a new secure Supabase RPC `delete_lead_for_current_user`, and falls back to a verified direct delete only if the RPC has not been installed yet.
- Added `supabase/migrations/0013_delete_lead_rpc.sql`, which verifies the authenticated user can access the lead through account membership, `user_id`, or `created_by`, deletes known lead-related rows that can block deletion, then deletes the lead.
- Validation for lead delete RPC fix: `dart format lib/main.dart`, `flutter analyze`, and `flutter test` passed with 114 tests.

### 2026-06-26

- Built Step 3 of the Market Coverage OS 2.0 design system: domain components for future screen redesigns.
- Added new design-system components only under `lib/design_system/components/`: `LeadCard`, `MissionCard`, `PropertyCard`, `EmptyState`, `LoadingState`, and `ErrorState`.
- Updated the design-system barrel export and debug gallery to preview the six domain components with realistic Lead, Mission, and ParcelProperty sample data.
- Preserved current app screens and did not modify `lib/main.dart`.
- Validation for domain components: `dart format lib/design_system/`, `flutter analyze`, and `flutter test` passed with 111 tests.
- Added a temporary Settings-tab debug button that opens the Design System Gallery so the new components can be tested on device.

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
- Added Drive map style switching in `lib/main.dart`: Auto follows theme, Dark uses Carto Dark Matter, light/Auto uses Carto Voyager, Minimal uses Carto Light, and Satellite uses Esri World Imagery.
- Added a small layers button on the Drive map to choose the map style and persist the choice in `SharedPreferences`.
- Fixed Property Preview readability/overlap by adding a solid sticky header with a top-right X close button and scrollable content underneath.
- Changed Lead Details to use a pinned top-right X close button.
- Improved mission recap dark-mode contrast for cards, metric text, and summary rows.
- Validation for map style/UI fix: `dart format lib/main.dart`, `flutter analyze`, and `flutter test` passed with 111 tests.
- Removed the unreadable Drive location status strip, made the Find Me/Following control smaller and state-colored, strengthened the map layers picker contrast, and fixed dark-mode readability for mission overlay pills.
- Removed the placeholder Business tab from bottom navigation and added account/log out controls to Settings.
- Improved Areas card text contrast in dark mode.
- Reordered Property Preview so lead action controls appear before property details.
- Removed the manual Standard map style option from the Drive map picker and made any old saved Standard preference fall back to Auto.
- Changed mission map parcel rendering so active missions can still draw parcel boundaries while tracking/follow mode is active.
- Added map-style-aware parcel outline colors: brighter parcel lines on satellite, lighter outlines on dark map tiles, and the existing darker outline on light tiles.
- Added lead deletion from the Leads tab row actions and Lead Details, both protected by a confirmation dialog and scoped through the existing account-scoped Supabase lead delete.
- Validation for map/delete fixes: `dart format lib/main.dart`, `flutter analyze`, and `flutter test` passed with 111 tests.
- User reported lead deletion still said "Could not delete lead" on-device.
- Tightened lead deletion to verify Supabase actually deletes a row, log the technical delete failure in debug mode, show a clearer RLS/permission message, and clean up lead photo storage after successful deletion.
- Added `supabase/migrations/0012_lead_delete_policy.sql`, a small RLS/grant migration for account-member lead deletes.
- Validation for lead delete follow-up: `dart format lib/main.dart`, `flutter analyze`, and `flutter test` passed with 111 tests.

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

> Read `AGENTS.md`, `MASTER_PLAN.md`, `docs/master_plan.md`, `PROJECT_STATUS.md`, `CODEX_CHECKLIST.md`, and `docs/project_journal.md` first before making changes.
