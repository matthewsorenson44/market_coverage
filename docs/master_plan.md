# Market Coverage OS Master Plan

## Product North Star

Market Coverage OS is a full wholesaler automation OS.

It answers three daily questions:

1. Where should I drive next?
2. What leads came in today?
3. What needs my attention right now?

Market Coverage OS = Drive OS + Lead Funnel + Today Queue + Automation Engine + Lightweight CRM + Deal Tools.

The map remains the product moat. It helps wholesalers see coverage, plan drive areas, capture field leads, and understand where opportunity has already been worked. But retention comes from acting on leads and automating follow-up. V1 must make the user better at both: finding new opportunities and managing every lead that enters the business.

## Final V1 Positioning

Market Coverage OS is not just a driving-for-dollars app.

V1 should become a practical daily command center for real estate wholesalers:

- Drive markets with live map coverage.
- Capture distressed properties quickly.
- Receive and organize leads from multiple sources.
- Know what came in today.
- Know what needs action now.
- Track follow-ups, reminders, status, and source.
- Export leads for skip tracing.
- Import enriched CSV results.
- Manage lightweight deal math and next steps.

The product should feel like:

> Apple Maps for market coverage plus a wholesaler lead funnel and daily action queue.

V1 should not try to replace a full enterprise CRM. It should focus on speed, clarity, and daily execution for solo wholesalers and small operators.

## What V1 Is / Is Not

V1 is:

- A Drive OS for market coverage and quick capture.
- A lead funnel for field, manual, CSV, referral, social, website, and other lead sources.
- A Today Queue for what needs attention now.
- A lightweight inbox surface inside Today for leads/items that need review.
- A lightweight CRM for status, source, score, tasks, reminders, photos, notes, and deal fields.
- A practical deal tool for ARV, repair cost, assignment fee, and MAO.
- A system that works even when owner or parcel data is unavailable.

V1 is not:

- A full enterprise CRM.
- A nationwide parcel ownership database.
- A skip tracing provider.
- A full marketing automation suite.
- A full calendar replacement.
- A full route optimization engine.
- A team/account permissions product yet.
- A fake-data product that pretends every market is ready.

Owner data is not required for MVP. Parcel boundaries and ownership data are optional by market.

If owner data is unavailable, the app should show:

> Owner data not available. Export this lead list for skip tracing.

Lead capture must never be blocked because parcel, owner, or enrichment data is missing.

## App Navigation

Target V1 navigation order:

1. Today
2. Drive
3. Inbox
4. Leads
5. Markets

Important current-state note:

The current shipped app has 5 tabs:

1. Today
2. Drive
3. Leads
4. Areas
5. Settings

Today exists as a shell with a real tasks section. Drive Next and Inbox are placeholders. Inbox and Markets do not exist yet as first-class tabs. Areas remains the bridge toward Markets.

Navigation intent:

- Today: the command center. Shows overdue tasks, today's follow-ups, mission prompts, and key alerts.
- Drive: live map, GPS, quick capture, missions, route tracking, and street coverage.
- Inbox: unified lead intake review from CSV imports, manual entries, driving leads, and later website/webhooks.
- Leads: searchable/filterable CRM list and lead detail management.
- Markets: market selection, city readiness, street data status, drive areas, and coverage planning.

Areas should eventually move under Markets or Drive as Drive Areas. Keep the tab named Areas until the 5-tab target navigation ships.

## Revised Domain Model

Core objects:

- Market: a city or local market the user works.
- Drive Area: a bounded area inside a market.
- Mission: a planned driving session inside a drive area.
- Street Segment: a real street centerline used for coverage tracking.
- Street Coverage: whether a street segment has been covered.
- Driving Point: GPS breadcrumb from route tracking.
- Lead: a property/opportunity captured from any source.
- Lead Source: currently stored as `leads.source` using the implemented 13-value taxonomy.
- Inbox Item: user-facing review item generated from lead workflows and, later, inbound events.
- Task: a follow-up, reminder, call, revisit, or action item.
- Mission Link: for V1, leads captured during a mission should be connected directly to that mission when possible.
- Inbound Event: later raw lead intake event from website, webhook, CSV, or future integrations.
- Attribution Link: later evidence trail between a lead and its source, mission, campaign, import, or inbound event.
- Photo: image attached to a lead.
- Deal Tool Fields: ARV, repair cost, assignment fee, and MAO.
- Score Signals: condition tags and scoring inputs such as roof damage, tall grass, vacancy, trash, exterior wear, and broken windows.

Existing lead source taxonomy:

- `driving`
- `referral`
- `facebook`
- `instagram`
- `tiktok`
- `youtube`
- `x`
- `mailing`
- `bandit_signs`
- `website`
- `manual`
- `csv_import`
- `other`

## Supabase Data Model

Current important tables:

- `leads`
  - Stores lead records.
  - Lead source is already implemented as a `source text` column with a 13-value CHECK constraint:
    - `driving`
    - `referral`
    - `facebook`
    - `instagram`
    - `tiktok`
    - `youtube`
    - `x`
    - `mailing`
    - `bandit_signs`
    - `website`
    - `manual`
    - `csv_import`
    - `other`
  - Do not replace this with a dedicated source table in V1.
  - `leads.source` is the quick label; future `attribution_links` is the evidence trail. They are complementary, do not consolidate them.
  - For V1, add/use a single nullable `mission_id` on `leads` at capture time where practical so mission recap can reliably show leads captured during that mission.
  - Before scheduling attribution work, document how the current mission recap computes "Attributed leads - tap to review leads from this mission" and whether a mission identifier already exists in some form.
  - Expected key columns include: `id`, `user_id`, `address`, `latitude`, `longitude`, `source`, `mission_id`, `pipeline_stage`, `status`, `score`, `notes`, `created_at`, `updated_at`.

- `driving_points`
  - Stores GPS route breadcrumbs.
  - Currently scoped by `user_id`.

- `street_coverage`
  - Stores covered street records.
  - Currently scoped by `user_id`.

- `city_streets`
  - Stores imported street centerline data for market coverage.
  - Supports coverage percentages and street rendering.

- `lead_photos`
  - Stores metadata for photos attached to leads.
  - Storage files live in Supabase Storage.

V1 tables and fields to document and build:

Timestamp columns on new tables should match the confirmed existing database convention from T1: `created_at` and `updated_at` where applicable.

- `tasks`
  - Purpose: explicit user actions such as call seller, revisit property, follow up, send mail, review lead, or complete skip trace.
  - Expected key columns: `id`, `user_id`, `lead_id`, `area_id`, `mission_id`, `title`, `description`, `status`, `priority`, `due_at`, `completed_at`, `created_at`, `updated_at`.

- `inbox_items`
  - Purpose for V1: unified review queue inside Today for new leads and items created by driving, manual creation, and CSV import. Website/webhook-fed inbox events are a fast-follow.
  - Expected key columns: `id`, `user_id`, `lead_id`, `title`, `subtitle`, `source`, `priority`, `status`, `due_at`, `resolved_at`, `created_at`, `updated_at`.

- `leads.mission_id`
  - Purpose for V1: simple mission attribution at capture time without introducing a parallel attribution system.
  - Expected behavior: if a lead is created during an active mission, save the active mission id on the lead when possible.

Fast-follow / 1.1 tables, not V1 beta requirements:

- `inbound_events`
  - Purpose: raw event log for website forms, webhooks, and future integrations.
  - Expected key columns later: `id`, `user_id`, `source`, `external_id`, `payload`, `received_at`, `processed_at`, `status`, `created_lead_id`, `error_message`, `created_at`, `updated_at`.

- `attribution_links`
  - Purpose: evidence trail connecting leads to source events, missions, campaigns, imports, or manual source selections.
  - Expected key columns later: `id`, `user_id`, `lead_id`, `source`, `inbound_event_id`, `mission_id`, `campaign_name`, `metadata`, `created_at`.

- `calendar_items`
  - Cut from V1. Tasks with `due_at` already feed Today.
  - Calendar can return in 1.1 as views over tasks, not as a parallel scheduling system.

Known future migration:

- `leads`, `driving_points`, and `street_coverage` are currently scoped by `user_id`.
- A future migration should convert these to `account_id` scoping before team features ship.
- Do not change this now. Document it as a known migration for the team/account phase.

Later data model upgrade:

- `lead_sources`
  - This is not a V1 replacement for `leads.source`.
  - Add this in Version 1.1 when source metadata is needed, such as per-channel cost, campaign grouping, display ordering, channel type, and ROI reporting.

Preserved status:

- Phase 0 security/RLS is complete and verified.
- R1 lead source tracking is complete and verified on device.

Do not reopen or contradict those settled items unless a new concrete regression is found.

## Build Phases

Each phase should be an ordered vertical slice that ships something testable.

### Phase 0: Security/RLS Foundation

Status: complete and verified.

Purpose:

- Ensure Supabase security is usable.
- Keep RLS enabled.
- Keep photo uploads working.
- Keep Flutter using anon key only.
- Avoid service role key in the client.

### R1: Lead Source Tracking

Status: complete and verified on device.

Purpose:

- Add `source` to `leads`.
- Use the 13-value source taxonomy.
- Preserve existing driving and manual lead creation.
- Show source clearly in lead workflows.
- Confirm source dropdown labels and colored lead-card chips on device.

### T1: Tasks Data Layer

Status: complete.

Purpose:

- Add the `tasks` table.
- Add the ability to create, view, and complete a task attached to a lead.

Testable result:

- User can create a task on a lead and mark it complete; it persists.

### T2: Today View

Status: complete as a shell with real tasks.

Purpose:

- Build the Today command-center tab.
- Surface today's follow-ups and overdue tasks.
- Keep Drive Next and Inbox as structured placeholders for later slices.

Testable result:

- User opens Today and sees real task-based attention items.

### DEV1: Mac Deploy Loop

Purpose:

- Add `scripts/mac_deploy.sh` and/or `docs/mac_testing.md` with exact copy-paste commands for the Mac.
- Include the real repo path, `git pull`, `flutter pub get`, and `flutter run --release` to iPhone.
- Unblock field confirmation of pushed fixes.

Testable result:

- User can pull the latest build on the Mac and run it on iPhone without guessing commands.

### DEV2: Build Identity

Purpose:

- Show app version, build number, and git commit hash in Settings.
- Make every device bug report and confirmation traceable to an installed build.

Testable result:

- Settings shows a build hash that can be copied into journal confirmations.

### FIELD1: Structured Field-Validation Drive

Purpose:

- Create/use a checklist for the "Needs Real Driving Test" items.
- Burn down the awaiting-confirmation backlog on a fresh build.

Testable result:

- Journal entries can move from "awaiting confirmation" to confirmed or reopened with build hash evidence.

### FIX-GPS1: Idle GPS Drift

Purpose:

- Gate route-point recording on speed threshold, GPS accuracy around 25m, and minimum displacement.
- Unit-test the filter in `lib/src/`.

Testable result:

- Sitting idle no longer draws a blue route line from GPS noise.

### FIX-SCORE1: Scoring Credibility

Purpose:

- Flag entity owners such as LLC, TRUST, INVESTMENTS patterns.
- Flag non-residential/multi-unit property types.
- Flag recent sales, for example sold within 12 months.
- Label these as "not a typical driving-for-dollars target."
- Use neutral styling for zero/unknown scores; never render score 0 as green.
- Keep capture available.
- Degrade honestly where parcel data is absent: "property type unknown."
- Never fake data.

Testable result:

- Commercial/entity-owned/recently sold properties no longer look like normal green driving-for-dollars targets.

### STAT1: Coverage Number Source Of Truth

Purpose:

- Reconcile street counts across screens.
- Investigate examples like Choose Market showing 1000 while Areas market card shows 3323 for the same market.
- Make session estimates consistent when preview and recap disagree.

Testable result:

- The same market and area show consistent street counts and session estimates across Drive, Areas, Today, and mission recap.

### UX-LEADCARD1: Lead List Card Hierarchy

Purpose:

- Make address the title and owner name secondary.
- Remove per-row trash icon; delete lives in Lead Details behind confirmation.
- Ensure "New Lead" chip is not red/danger.
- Use a neutral chip for score 0.
- Clarify or hide raw sale tags like "date $0."

Testable result:

- Lead cards scan cleanly and no destructive action sits on every row.

### DN1: Drive Next On Today

Purpose:

- Fill the Today tab's Drive Next hero card with the existing mission planner output.
- Show active area coverage %, next-session estimate, streets, minutes, and coverage gain.
- Add a one-tap "Plan Today's Drive" action that opens the existing mission flow.
- Do not build new recommendation logic; reuse the mission preview computation.

Testable result:

- User opens Today and sees their active area's coverage state and can start planning a drive in one tap.

### UX-AREA3: Areas Tab Restructure

Purpose:

- Restructure Areas around active market, clean area rows, and a clearer mission entry point.
- Keep tab named Areas until the target Markets tab ships.

Testable result:

- User can understand active market, active area, area progress, and the one primary action without row-level clutter.

### MAP-AREA1: Drive Map Area Overlay

Purpose:

- Upgrade area overlays on the Drive map without changing map tiles.
- Make active, other, and completed areas visually distinct.

Testable result:

- User can see which area is active, which areas exist nearby, and which territory is complete at a glance.

### MAP-TOGGLE1: Independent Map Layer Toggles

Purpose:

- Let Streets and Parcels be toggled independently regardless of area selection.

Testable result:

- User can show all streets, show all parcels, or hide either layer without first selecting an area.

### RR1: Consolidate Revisit Reminders Into Tasks

Purpose:

- Replace or map legacy Revisit Reminder fields into Tasks.
- Make Today the single source of truth for what needs attention.

Testable result:

- Setting a revisit reminder on a lead makes it appear in Today when due.

### D1a: Capture-Time Dedupe Flag

Purpose:

- Reuse parcel/address matching already used by parcel-tap capture.
- Flag likely duplicates at capture time.
- Do not aggressively merge records.

Testable result:

- Capturing an already-known property warns the user before creating duplicate clutter.

### C1: CSV Lead Import

Purpose:

- Reuse existing CSV plumbing.
- Import lead rows from skip tracing or external lists.
- Default source to `csv_import`.
- Match back to existing leads where possible.

Testable result:

- User imports a CSV and sees matched/enriched leads or clear unmatched rows.

### T3-lite: Inbox Surface Inside Today

Purpose:

- Add/use `inbox_items`.
- Surface unreviewed items inside Today from CSV imports, manual leads, and driving leads only.
- No website/webhook logic in this slice.

Testable result:

- User can see and clear an inbox item from Today.

### CRM1: Lightweight CRM Polish

Purpose:

- Make lead detail and lead list easier to act from.
- Emphasize source, status, score, next task, notes, photos, and deal math.
- Keep the CRM lightweight and action-first.

Testable result:

- User can open a lead and immediately know the next action.

### BETA1: TestFlight Beta

Purpose:

- Distribute via TestFlight to the founder plus 2 external wholesalers.
- Review first-run experience, onboarding path, empty states, crash reporting, and feedback loop.
- Testers are independent accounts; RLS isolation is already verified in Phase 0.

Testable result:

- Two external users can install, create accounts, set up a market, and drive without founder assistance.

### B1: Billing & Subscription

Purpose:

- V1 launches as a paid subscription after beta feedback.
- Because distribution is the Apple App Store, subscriptions must use Apple in-app purchase, such as RevenueCat for Flutter, not external web checkout.
- Scope one subscription product, purchase/restore flow, entitlement gating after a trial or paywall, and a simple "manage subscription" link to iOS settings.
- App Store Connect setup can begin in parallel with beta work.

Testable result:

- A fresh account hits the paywall, can subscribe in sandbox, and entitlement unlocks the app.

### Drive OS Foundation

Status: substantially built.

Purpose:

- Preserve and polish the existing moat.
- Continue improving markets, drive areas, missions, coverage, quick capture, and GPS reliability.

Testable result:

- User can drive, capture leads, see coverage, and complete missions reliably.

Drive OS is already a foundation, not net-new V1 work.

## Near-Term Task Queue

Take the top task unless the user explicitly says otherwise.

1. DEV1 - Mac deploy loop.
2. DEV2 - Build identity.
3. FIELD1 - Structured field-validation drive.
4. FIX-GPS1 - Idle GPS drift.
5. FIX-SCORE1 - Scoring credibility thin slice.
6. STAT1 - Single source of truth for coverage numbers.
7. UX-LEADCARD1 - Lead list card hierarchy.
8. DN1 - Real Drive Next card on Today.
9. UX-AREA3 - Areas tab restructure.
10. MAP-AREA1 - Drive map area overlay upgrade.
11. MAP-TOGGLE1 - Independent Streets and Parcels toggles.
12. RR1 - Consolidate revisit reminders into tasks.
13. D1a - Capture-time dedupe flag.
14. C1 - CSV lead import.
15. T3-lite - Inbox surface inside Today.

## UX-AREA3 Spec

Keep the tab named Areas for now; rename to Markets only when the 5-tab target ships.

Restructure to one hierarchy with the active market as the page header:

- Header: active market name, readiness one-liner, and "Switch market" affordance.
- Do not show raw zero stats such as "0 properties - 0 targets" on summary cards. Show meaning instead, such as "Ready to drive - 3 areas - 4 leads."
- Keep data-layer detail inside market detail.
- Overview map panel under the header: use the existing `flutter_map` widget, non-interactive, drawing all of the market's area polygons tinted by coverage.
- Area polygon tint: green = done, amber = in progress, dashed outline = no street data.
- Area rows: name, coverage progress bar, "X of Y streets - N leads" caption, and Active badge where relevant.
- One primary button, Start Mission, on the active area only.
- Open detail on row tap.
- Move Find Motivated Sellers, renamed to "Analyze properties", Set Active, Mark Complete, and Delete into the area detail screen.
- Remove per-row trash icons.
- Area creation: "New area" leads to drawing on the map.
- Auto-suggest a unique name from geography, such as "Owasso NE."
- Block or warn on duplicate names within a market.
- Gate or clearly label Start Mission when an area has no street data loaded.
- Remove duplicated explainer copy on area detail.

## MAP-AREA1 Spec

The map style/tiles stay as they are. Only the area overlay changes.

Visual states:

- Active area: bold outline, red/green street coverage rendering inside it, small floating label pill with name, coverage %, and streets remaining.
- Other areas: quiet tinted polygons with low-opacity name/percent labels.
- Completed areas: green tint so covered territory is visible at a glance.
- Tap any area polygon to make it active. This replaces most uses of the Set Active button.
- Uncovered street rendering stays scoped to the active area.

## Interface Principles

- Progressive disclosure: every screen has a summary layer always visible and a detail layer that expands in place. Popups/modals only for decisions, such as confirm delete or pick date, never for information. Dropdowns only choose one value, never hide content.
- One primary action per screen, stated as a verb. Other actions are demoted or moved into detail screens.
- One-line muted captions under section headers teach the app, such as "Enter ARV to get your max offer." No onboarding tour or coach marks in V1. If a screen needs a tour, restructure the screen.
- Show a stat's meaning, not raw stat dumps. Never surface zero-value data layers on summary cards.
- Lead Details should be reorganized to: summary header with address, score, stage and source chips; Next Action card; collapsed sections for Owner and contact, Deal math, Property record, Photos and notes.
- Stop writing county parcel-import data into Notes for new leads; structured fields already exist for it.
- Gate the "Open Design Gallery" Settings button behind debug builds.

## V1 Launch Cut Line

### Tier 1: 1.0 Beta Cut Line

Required before TestFlight external testers:

1. Drive OS: markets, areas, missions, coverage, and quick capture.
2. Tasks: T1 complete.
3. Today with real Drive Next: DN1.
4. Revisit reminders consolidated into tasks: RR1.
5. Leads CRM with source tracking: done and confirmed on device.
6. CSV export: done.
7. CSV lead import: C1.
8. Capture-time dedupe flag: D1a.
9. Property-scoring credibility guardrails: FIX-SCORE1.
10. GPS idle-drift fix: FIX-GPS1.
11. Coverage integrity confirmed in the field on a fresh build.

### Tier 2: 1.0 App Store Cut Line

After beta feedback:

1. Billing via Apple IAP: B1.
2. Inbox surface in Today fed by CSV imports, manual leads, and driving leads only: T3-lite, no webhooks.
3. CRM polish informed by beta feedback.

Drive OS is already substantially built and remains the product moat.

Funneling, Today Queue, and automation are not later ideas. They are core to V1, but webhooks and advanced attribution are not required before beta.

V1 can defer:

- Dedicated `lead_sources` table.
- Advanced source ROI analytics.
- Campaign cost tracking.
- Full team/account permissions.
- Full account-based scoping migration.
- Full calendar sync.
- Full marketing automation sequences.
- Native push notification polish.
- Advanced route optimization.
- AI lead scoring.
- Nationwide owner/parcel data.

## 1.0.x Fast-Follow

Explicitly out of V1 beta and App Store cut:

- W1 Website/Webhook Intake and `inbound_events` processing.
- A1 Attribution Links table. V1 should use a single nullable `leads.mission_id` set at capture time. Before scheduling A1, document how mission recap currently computes "Attributed leads - tap to review leads from this mission" and whether `mission_id` already exists in some form.
- K1 Calendar Cut. Tasks with `due_at` already feed Today. Calendar becomes a 1.1 candidate implemented as views over tasks, not a fully parallel table.

## Version 1.1 Roadmap

Version 1.1 focuses on analytics, automation depth, team readiness, channel optimization, and selected fast-follow items after V1 stabilizes.

Potential Version 1.1 upgrades:

- Add `lead_sources` table for source metadata.
- Track source cost by channel and campaign.
- Track ROI by source.
- Add campaign-level attribution.
- Add `attribution_links` once evidence trails are needed.
- Add `inbound_events` for website/webhook intake.
- Add website/webhook intake.
- Add team/account scoping with `account_id`.
- Add roles and permissions.
- Add source dashboards.
- Add channel analytics.
- Add integrations for Zapier, Make, n8n, website forms, and lead vendors.
- Add direct mail campaign tracking.
- Add skip trace vendor templates.
- Add recurring automation rules.
- Add notification scheduling.
- Add calendar views over tasks.
- Add route-to-start and routing optimization.
- Add market readiness analytics.
- Add more property data providers by market.
- Add richer dedupe and merge workflows.

## Codex Prompt Template

Use this checklist for every code task:

```text
Read AGENTS.md, MASTER_PLAN.md, docs/master_plan.md, PROJECT_STATUS.md, CODEX_CHECKLIST.md, and docs/project_journal.md before coding.

You must follow these steps exactly:

1. Identify the single Task ID being implemented.
2. Restate the task goal in 2-4 sentences.
3. List the exact files you expect to touch before making edits.
4. Do not work on later tasks.
5. Do not perform unrelated refactors.
6. Preserve existing behavior unless the task explicitly changes it.
7. If database changes are needed, create a Supabase migration in supabase/migrations and note any backfill assumptions.
8. If API/webhook/edge function changes are needed, keep them minimal and scoped to the task.
9. Add or update focused tests where practical.
10. After coding, run:
   - dart format .
   - flutter analyze
   - flutter test
11. If a command fails, report the exact failure instead of silently skipping it.
12. Update PROJECT_STATUS.md with:
   - current phase
   - completed task ID
   - files changed
   - migration added
   - test results
   - known issues
   - next recommended task
13. Update docs/project_journal.md with:
   - what changed
   - what was validated
   - which bugs are still open
   - which bugs were fixed and are waiting for user confirmation
   - which bugs the user confirmed are fixed
14. Do not start a new feature phase while more than 5 fixes sit at "fix pushed, awaiting user confirmation"; prioritize DEV/FIELD tasks to burn the backlog down.
15. After DEV2 ships, tie every on-device bug report or fix confirmation to the build hash shown in Settings. Journal confirmation entries must record the build hash.
16. New features should go in new files under lib/src/ or lib/features/ where practical, not appended to lib/main.dart. Extract existing code from main.dart only when a task already touches that code; never as a standalone rewrite.
17. PROJECT_STATUS.md owns the ordered queue. Each session takes the top task unless the user says otherwise; completed tasks move to a short "Recently completed" list.
18. Then provide a short summary of what changed and any follow-up risks.

Commit message format:
<type>(<scope>): <TASK ID> <desc>

Examples:
feat(inbox): T3-lite add inbox item model
feat(today): DN1 add drive next card
refactor(data): R1 add lead source model
fix(dedupe): D1a flag duplicate lead candidates

Hard rules:
- One task per session.
- No broad rewrites.
- No hidden assumptions about future tasks.
- Keep code small, reviewable, and shippable.
```

## Product Philosophy Reminder

Market Coverage OS should be built around daily execution.

The map is the moat, but the business value is the full loop:

1. Find where to drive.
2. Capture leads quickly.
3. Collect leads from every source.
4. Know what came in today.
5. Know what needs action now.
6. Follow up consistently.
7. Export, enrich, score, and work deals.

Capture first. Enrich later.

Do not fake owner names. Do not require nationwide parcel data for MVP. Do not block lead creation because a parcel lookup fails. Do not pretend a market is ready when data is missing.

A useful lead can start with only:

- GPS location
- Address if available
- Source
- Photos
- Tags
- Notes
- Score
- Follow-up task

The system should then help the user turn that raw lead into an organized opportunity.

V1 wins when a wholesaler opens the app and immediately knows:

1. Where should I drive next?
2. What leads came in today?
3. What needs my attention right now?
