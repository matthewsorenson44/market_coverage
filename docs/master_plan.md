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
- A unified Inbox for incoming and unreviewed leads.
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

The current shipped app has 4 tabs:

1. Drive
2. Leads
3. Areas
4. Settings

The 5-tab structure is the V1 target to build toward, not the current state. Today and Inbox do not exist yet.

Navigation intent:

- Today: the command center. Shows new leads, overdue tasks, today's follow-ups, mission prompts, and key alerts.
- Drive: live map, GPS, quick capture, missions, route tracking, and street coverage.
- Inbox: unified lead intake review from website/webhooks, CSV imports, manual entries, and future integrations.
- Leads: searchable/filterable CRM list and lead detail management.
- Markets: market selection, city readiness, street data status, drive areas, and coverage planning.

Areas should eventually move under Markets or Drive as Drive Areas. The current Areas tab is a bridge toward the V1 Markets structure.

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
- Inbound Event: raw lead intake event from website, webhook, CSV, or future integrations.
- Inbox Item: user-facing review item generated from inbound events or lead workflows.
- Task: a follow-up, reminder, call, revisit, or action item.
- Attribution Link: connection between a lead and its source, mission, campaign, import, or inbound event.
- Calendar Item: lightweight scheduled follow-up, drive block, appointment, or reminder.
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
  - Expected key columns include: `id`, `user_id`, `address`, `latitude`, `longitude`, `source`, `pipeline_stage`, `status`, `score`, `notes`, `created_at`, `updated_at`.

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

New V1 tables to document and build:

Timestamp columns on new tables should match the existing database convention. Existing tables use `created` and `updated` where applicable, not `created_at` and `updated_at`. New tables should follow the existing convention for consistency; confirm the exact existing column names before writing migrations.

- `inbound_events`
  - Purpose: raw event log for inbound leads from website forms, webhooks, CSV imports, and future integrations.
  - Expected key columns: `id`, `user_id`, `source`, `external_id`, `payload`, `received_at`, `processed_at`, `status`, `created_lead_id`, `error_message`, `created_at`.

- `inbox_items`
  - Purpose: unified review queue for new inbound leads, import rows, follow-up prompts, and items needing user action.
  - Expected key columns: `id`, `user_id`, `lead_id`, `inbound_event_id`, `title`, `subtitle`, `source`, `priority`, `status`, `due_at`, `resolved_at`, `created_at`.

- `tasks`
  - Purpose: explicit user actions such as call seller, revisit property, follow up, send mail, review lead, or complete skip trace.
  - Expected key columns: `id`, `user_id`, `lead_id`, `area_id`, `mission_id`, `title`, `description`, `status`, `priority`, `due_at`, `completed_at`, `created_at`, `updated_at`.

- `attribution_links`
  - Purpose: connect leads to source events, missions, campaigns, imports, or manual source selections.
  - Expected key columns: `id`, `user_id`, `lead_id`, `source`, `inbound_event_id`, `mission_id`, `campaign_name`, `metadata`, `created_at`.

- `calendar_items`
  - Purpose: lightweight scheduling for follow-ups, appointments, drive sessions, and reminders.
  - Expected key columns: `id`, `user_id`, `lead_id`, `task_id`, `area_id`, `market_id`, `title`, `starts_at`, `ends_at`, `status`, `created_at`, `updated_at`.

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
- R1 lead source tracking is complete and verified.

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

Status: complete and verified.

Purpose:

- Add `source` to `leads`.
- Use the 13-value source taxonomy.
- Preserve existing driving and manual lead creation.
- Show source clearly in lead workflows.

### T1: Tasks Data Layer

Purpose:

- Add the `tasks` table.
- Add the ability to create, view, and complete a task attached to a lead.

Testable result:

- User can create a task on a lead and mark it complete; it persists.
- This slice does not build the Today tab.

### T2: Today View

Purpose:

- Build the Today command-center tab.
- Surface today's follow-ups, overdue tasks, new leads, and a suggested next action.
- Read from the tasks created in T1.

Testable result:

- User opens Today and immediately sees what needs attention.

### T3: Inbox Surface Inside Today

Purpose:

- Add `inbox_items`.
- Surface unreviewed inbound items inside Today.
- Let user review, resolve, or convert items.

Testable result:

- User can see and clear an inbox item from Today.

### L1: Manual Source-Based Lead Creation

Purpose:

- Let users manually create leads with the existing 13-source list.
- Use `leads.source`.
- Do not introduce `lead_sources` table in V1.

Testable result:

- User creates a manual lead from a selected source and sees it correctly in Leads.

### C1: CSV Import For Leads

Purpose:

- Reuse existing CSV plumbing.
- Import lead rows from skip tracing or external lists.
- Default source to `csv_import`.
- Create leads or inbox review items depending on confidence.

Testable result:

- User imports a CSV and sees resulting leads or review items.

### A1: Source Attribution

Purpose:

- Add `attribution_links`.
- Add/use `inbound_events`.
- Connect leads to missions, imports, webhooks, and source campaigns.

Testable result:

- A lead can show where it came from and why.

### W1: Website/Webhook Intake

Purpose:

- Accept website or webhook leads.
- Store raw payloads in `inbound_events`.
- Create `inbox_items` for review.
- Convert valid events into leads.

Testable result:

- A test webhook creates an inbox item and/or lead without manual database work.

### D1: Dedupe MVP

Purpose:

- Prevent duplicate leads once multiple sources are flowing in.
- Match by parcel ID when available.
- Otherwise match by normalized address + city + state.
- Flag duplicate candidates instead of aggressively auto-merging.

Testable result:

- Duplicate imported or inbound leads are flagged before cluttering the CRM.

### K1: Calendar MVP

Purpose:

- Add `calendar_items`.
- Schedule follow-ups, drive blocks, and reminders.
- Show upcoming items in Today.

Testable result:

- User can schedule a follow-up and see it in Today.

### CRM1: Lightweight CRM Polish

Purpose:

- Make lead detail and lead list easier to act from.
- Emphasize source, status, score, next task, notes, photos, and deal math.
- Keep the CRM lightweight and action-first.

Testable result:

- User can open a lead and immediately know the next action.

### Drive OS Foundation

Status: substantially built.

Purpose:

- Preserve and polish the existing moat.
- Continue improving markets, drive areas, missions, coverage, quick capture, and GPS reliability.

Testable result:

- User can drive, capture leads, see coverage, and complete missions reliably.

Drive OS is already a foundation, not net-new V1 work.

## V1 Launch Cut Line

V1 must include:

1. Tasks (T1)
2. Today Queue (T2)
3. Unified inbox (T3)
4. Manual source-based lead creation
5. CSV import
6. Website/webhook intake
7. Source attribution
8. Dedupe MVP
9. Calendar MVP
10. Lightweight CRM
11. Drive OS with markets, drive areas, missions, coverage, and quick capture

Drive OS is already substantially built and remains the product moat.

Funneling, Today Queue, and automation are not later ideas. They are core to V1.

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

## Version 1.1 Roadmap

Version 1.1 focuses on analytics, automation depth, team readiness, and channel optimization.

Potential Version 1.1 upgrades:

- Add `lead_sources` table for source metadata.
- Track source cost by channel and campaign.
- Track ROI by source.
- Add campaign-level attribution.
- Add team/account scoping with `account_id`.
- Add roles and permissions.
- Add source dashboards.
- Add channel analytics.
- Add integrations for Zapier, Make, n8n, website forms, and lead vendors.
- Add direct mail campaign tracking.
- Add skip trace vendor templates.
- Add recurring automation rules.
- Add notification scheduling.
- Add calendar sync.
- Add route-to-start and routing optimization.
- Add market readiness analytics.
- Add more property data providers by market.
- Add richer dedupe and merge workflows.

## Codex Prompt Template

Use this checklist for every code task:

```text
Read MASTER_PLAN.md, PROJECT_STATUS.md, CODEX_CHECKLIST.md, and docs/project_journal.md before coding.

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
14. Then provide a short summary of what changed and any follow-up risks.

Commit message format:
<type>(<scope>): <TASK ID> <desc>

Examples:
feat(inbox): R3 add inbox item model
feat(today): T2 add today command center
refactor(data): R1 add lead source model
fix(dedupe): V2 flag duplicate lead candidates

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
