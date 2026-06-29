# MASTER PLAN - Market Coverage OS

## What This App Is

Market Coverage OS is the daily acquisition command center for a part-time wholesaler.

It is not just a Driving for Dollars app. Driving for Dollars is the hook that gets users in. The unified lead funnel and the Today Queue are what keep users paying.

The one-line product promise:

> Open one app, see every seller lead from every source, know what needs attention today, and know where to drive next.

When the user opens the app they should immediately see:

- New leads from driving.
- New leads from ad platforms: Facebook, Instagram, TikTok, YouTube, and Google.
- New leads from website forms.
- New leads from email.
- New leads from phone and SMS.
- New leads from direct mail responses.
- Overdue follow-ups.
- Today's appointments.
- The next best area to drive.

## Critical Execution Rules

These rules exist because they have worked for every successful session so far. Breaking them is the fastest way to break a working app.

1. **Do not restructure the app.** The app lives in a single `lib/main.dart` plus the `lib/design_system/` folder. We are not migrating to a layered `lib/features/`, `lib/shared/`, and `lib/core/` architecture. New features are added additively, the same way the design system was added. A full refactor is the single most likely thing to break the working app and strand a half-migrated codebase. Do not do it.
2. **Every session ships something testable.** No session should add a database table or model with no UI yet. Each session is a thin vertical slice: table, screen, and one working flow the user can open and test. One working feature beats four empty tables.
3. **Additive only.** Never change existing capture, mission, scoring, CRM, photos, ARV/MAO, Drive Areas, Market Map, offline queue, or export/import behavior unless the task explicitly says to. Preserve all existing functionality. All existing tests must keep passing.
4. **Always provide a numbered How To Test checklist** at the end of every code task, written tap-by-tap, with a clear pass/fail condition.
5. **SQL is run by the human.** Codex outputs SQL and explains it; the human runs it in the Supabase SQL Editor. Codex never assumes it can run SQL.
6. **Git checkpoint before every session.** Run `git add .` and `git commit -m "..."` before any change when the user requests a checkpoint or the task is substantial.
7. **Validate every session.** Run `dart format .`, `flutter analyze`, and `flutter test`. Fix only issues the change introduced.
8. **Four tabs, not five.** The audit confirmed the 4-tab structure is correct and warned against overload. Today and Inbox overlap, so Inbox is a section inside Today, not its own tab, until and unless real use proves a separate tab is needed.
9. **No fake data, ever.** No fabricated owner names, phones, emails, or parcel data. Owner data is optional and never required to capture a lead.

## Current State

- Design system complete: tokens, primitives, domain components, and redesigned Drive tab in `lib/design_system/`.
- Dark/light mode with system follow and manual toggle in Settings.
- Map tile switching: Dark Matter, Voyager, Satellite, and Minimal.
- Frosted glass bottom sheets and transparent AppBar over map.
- Drive OS: markets, Drive Areas, Missions, street coverage, next-best-street, time-based mission planner, weekly planner, mission calibration, mission results.
- Quick Capture: GPS, reverse-geocoded address, tags, score, notes, and photos.
- Owner-data pivot: lead capture works nationwide on GPS and address; parcel/owner data is optional enhancement only.
- National market catalog: markets table, readiness states, Data Health.
- Multi-county street import: bbox-based, handles county-straddling cities.
- Offline lead save queue and sync.
- Field test logger.
- CSV export for skip tracing: column selection, `lead_id` locked.
- CSV import for skip tracing enrichment: `lead_id` first, address fallback, fill-blanks-only merge, preview before write.

## Revised V1 Navigation - Four Tabs

1. **Today** - the command center. First tab. Opens here. The unified Inbox lives as a section inside Today, not a separate tab.
2. **Drive** - the Driving for Dollars map experience.
3. **Leads** - the CRM list and lead detail.
4. **Markets** - market catalog, Drive Areas, and Data Health.

Settings remains accessible by gear or account. Analytics is a possible later tab, not V1.

## The Four Product Pillars

### Pillar 1 - Drive OS

Mostly done.

Markets, Drive Areas, Missions, street coverage, next best street, Quick Capture, parcel support where available, mission results, coverage percentage, and leads found during missions.

### Pillar 2 - Lead Funnel OS

The new work.

Manual lead entry, field capture, website/webhook leads, CSV import from ad platforms, source tracking, campaign tracking, and duplicate detection.

Future connectors: Facebook, Instagram, TikTok, YouTube, Google, X, Gmail, and Twilio.

### Pillar 3 - Today Queue

The retention engine.

New leads needing review, leads needing contact today, overdue follow-ups, revisit reminders, appointments, inbound replies, suggested driving mission, and do-this-next recommendations.

### Pillar 4 - Lightweight CRM

Partly done.

Lead stages, lead detail, notes, photos, tasks, calendar items, follow-up status, source attribution, mission attribution, ARV, repair estimate, and MAO.

This should not become a full REsimpli clone.

## Data Model

Add these tables additively alongside existing tables. Each table should be introduced in the session that first uses it. Do not add empty tables ahead of UI.

### `lead_sources`

Tracks where every lead came from.

Columns: `id`, `user_id`, `name`, `source_type`, `platform`, `campaign_name`, `is_active`, `created_at`, `updated_at`.

Source types: `field`, `manual`, `website`, `facebook`, `instagram`, `tiktok`, `youtube`, `google_ads`, `x`, `gmail`, `email`, `phone`, `sms`, `direct_mail`, `referral`, `csv_import`, `webhook`, `other`.

### `tasks`

Powers the Today Queue.

Columns: `id`, `user_id`, `lead_id`, `market_id`, `drive_area_id`, `mission_id`, `title`, `description`, `task_type`, `priority`, `due_at`, `completed_at`, `status`, `source`, `created_at`, `updated_at`.

Task types: `review_new_lead`, `call_lead`, `text_lead`, `email_lead`, `mail_lead`, `drive_by`, `appointment`, `follow_up`, `update_lead`, `sync_issue`.

### `inbound_events`

Raw lead events from outside the app, before or while they become leads.

Columns: `id`, `user_id`, `source_id`, `external_event_id`, `raw_payload`, `normalized_name`, `normalized_phone`, `normalized_email`, `normalized_address`, `normalized_message`, `campaign_name`, `status`, `lead_id`, `received_at`, `processed_at`, `created_at`.

Statuses: `new`, `processed`, `duplicate`, `needs_review`, `failed`, `ignored`.

### `inbox_items`

The unified inbox item shown to the user inside Today.

Columns: `id`, `user_id`, `inbound_event_id`, `lead_id`, `item_type`, `title`, `subtitle`, `body`, `priority`, `status`, `due_at`, `created_at`, `updated_at`.

Item types: `new_field_lead`, `new_ad_lead`, `new_web_lead`, `new_email_lead`, `new_sms_lead`, `missed_call`, `voicemail`, `direct_mail_response`, `duplicate_candidate`, `follow_up_due`, `appointment_due`, `sync_error`.

### `calendar_items`

In-app calendar before external Google Calendar sync.

Columns: `id`, `user_id`, `lead_id`, `task_id`, `title`, `starts_at`, `ends_at`, `location`, `notes`, `status`, `created_at`, `updated_at`.

### `attribution_links`

Connects a lead to its origin.

Columns: `id`, `user_id`, `lead_id`, `source_id`, `market_id`, `drive_area_id`, `mission_session_id`, `campaign_name`, `created_at`.

### Existing Tables

Existing tables remain unchanged: `leads`, `driving_points`, `street_coverage`, `city_streets`, `drive_areas`, `properties`, `missions`, `weekly_plans`, `markets`, plus the `lead-photos` storage bucket.

## Security

Security must be done before public launch. This is non-negotiable.

This plan adds tables full of phone numbers, emails, and raw inbound payloads. Security cannot be deferred again. The funnel multiplies sensitive data, so the isolation gap must close before the funnel tables fill up and definitely before any second user or App Store release.

### Security Gate 1 - Do First, Before Funnel Tables

- Enable RLS on all existing tables, scoped to `auth.uid()`.
- Move lead photos to a private Supabase Storage bucket.
- Replace `getPublicUrl()` with signed URLs for photo access.
- Add Sentry or equivalent crash reporting.

### Security Gate 2 - Applied As Each New Table Is Created

- Every new funnel table gets RLS enabled and a `user_id`-scoped policy in the same session it is created.
- No new table ships without RLS.

### Security Gate 3 - Before App Store Submission

- Audit every table for RLS coverage.
- Confirm no public bucket exposure.
- Confirm webhook endpoints validate a secret token.
- Confirm no raw payloads leak PII in logs.

## Build Order

Each numbered item is one Codex session that produces something the user can open and test. No empty-table sessions.

### Phase 0 - Security Gate 1

Do before any funnel work.

- **0.1** RLS audit, read-only: output current RLS status of all tables and report what is exposed. No changes.
- **0.2** Enable RLS and policies on all existing tables. Private photo bucket plus signed URLs. Add Sentry.

### Phase R - Source Attribution

Thin slice, immediately visible.

- **R1** `lead_sources` table with RLS, source chip on lead cards, and source picker in the Add Lead form. Existing leads default to source type `field`. Lead Detail shows source.

Payoff: every lead now has visible attribution.

### Phase T - Today Queue Using Data Already In The App

- **T1** `tasks` table with RLS and task model. Add a minimal Today tab that shows three things from existing data only: follow-ups due, revisit reminders, and today's scheduled mission. No inbox yet.

Payoff: the app opens like a command center immediately, using data already in the app.

- **T2** Auto-create a task when a lead is created. Field lead creates a review task. Today now fills itself.

Payoff: Today is self-populating.

### Phase S - Multi-Source Funnel

- **S1** Manual source-based lead creation. Add source and campaign fields to the Add Lead form so a user can log a Facebook, website, or referral lead by hand. Source chip displays. Auto-task is created per source type.

Payoff: real multi-source funnel data exists.

- **S2** Inbox as a section inside Today, not a tab. Surface new and unreviewed leads needing action. Filter chips: All, Field, Ads, Website, Email, Phone, Mail, Errors.

Payoff: unified inbox without a fifth tab. Validate whether a separate tab is ever needed before building one.

- **S3** CSV import for ad leads. Reuse the existing CSV plumbing from skip-tracing import. Import Facebook, TikTok, and Google ad-export CSVs, normalize, create leads plus source plus campaign plus auto-task, and flag duplicates.

Payoff: ad leads flow in without API integration.

### Phase U - Website / Webhook Intake

Only after the in-app funnel is proven.

- **U1** `inbound_events` and `inbox_items` tables with RLS plus inbound webhook Edge Function. Accept POST, validate secret token, save raw event, normalize, create inbox item, and optionally create lead plus auto-task.

Payoff: external sources can send leads in.

- **U2** Website lead form setup screen in Settings. Show webhook URL, source token, sample payload, and a Send Test Lead button. Test lead appears in Today.

Payoff: user can connect a landing page.

- **U3** Landing page form template documentation. Docs only. No website builder.

### Phase V - Dedupe And Lead Identity

Last, because it only matters with multi-source.

- **V1** Normalize phone, email, and address while preserving originals.
- **V2** Duplicate detection MVP. Flag possible duplicates into the Today inbox section. Never auto-merge. User reviews and can mark ignored.

### Phase W - Connector Settings Hub

- **W1** Connector Settings screen. Website forms, CSV import, and manual entry are available. Gmail, Twilio, Facebook, Instagram, TikTok, Google, YouTube, and X are marked coming soon. No fake broken buttons.

### Phase X - Calendar MVP

- **X1** `calendar_items` table with RLS plus simple in-app calendar tied to leads and tasks. Appointments show in Today. No external Google Calendar sync yet.

### Phase Z - Launch Readiness

- **Z1** Security gate 3 audit: RLS coverage, bucket exposure, webhook tokens, PII in logs.
- **Z2** Verify Owasso data complete; finish Tulsa street import so there are two solid demo markets.
- **Z3** Remove debug tools, including the design gallery button and field test logger trigger, or hide them behind a debug flag.
- **Z4** App Store readiness pass.

## V1 Launch Cut Line

V1 must include:

- Driving for Dollars map, Markets, Drive Areas, Missions, street coverage, Quick Capture.
- Manual lead creation, lead source tracking, and source attribution.
- Today Queue and Tasks.
- Unified Inbox as a Today section.
- CSV import for ad leads plus existing skip-tracing export/import.
- Website/webhook intake.
- Basic duplicate detection.
- Mission attribution.
- Lightweight CRM.
- Calendar MVP.
- Offline save queue.
- RLS on every table plus private photo storage, with security gates 1 and 3 complete.
- App Store readiness.

V1 must not wait for:

- Official Facebook, Instagram, TikTok, YouTube, or X APIs.
- Full Gmail sync, full Twilio dialer, or full SMS campaign builder.
- Full email marketing or full ad manager.
- Full owner-data provider or full skip-tracing automation.
- AI agents.

## Strategic Summary

Driving for Dollars gets users in.

Lead funneling and the Today Queue keep users paying.

The moat is field coverage intelligence: the app knows what has actually been seen, by whom, how recently, with what signals, and what the next best action is. That gets fused with a unified funnel that makes the app the one place the user acts on every seller lead from every source.

Build it in additive vertical slices on top of the working app. Never restructure the whole app. Close the security gap before the funnel tables fill. Keep four tabs until use proves a fifth is needed.
