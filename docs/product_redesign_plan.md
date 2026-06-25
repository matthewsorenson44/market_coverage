# Market Coverage OS Product Redesign Plan

## North Star

Market Coverage OS should answer one question on every screen:

> What is the next best action to make me money?

The app is not a DealMachine clone. It should become the field operating system for real estate acquisition teams: fast enough for one-handed driving, intelligent enough to rank work, and polished enough to feel like a premium enterprise product.

## Core Product Principles

1. **Field first**
   - Large tap targets.
   - Minimal text while driving.
   - One-handed flows.
   - No modal clutter during active driving.

2. **Speed over feature count**
   - Default to the next action.
   - Hide secondary settings.
   - Reduce repeated choices.

3. **Intelligence over data**
   - Do not just show parcels, leads, and streets.
   - Rank them.
   - Explain what to do next.

4. **Trust before magic**
   - GPS, mission stats, route tracking, photos, and saved data must be reliable before advanced AI.
   - Every automated recommendation should show why it exists.

5. **Premium calm**
   - Dark-first field UI.
   - Sparse colors.
   - Strong typography.
   - Smooth panels.
   - No dashboard clutter.

## New Navigation Structure

Use five bottom tabs on mobile:

1. **Today**
   - The daily money dashboard.
   - Shows what to do now.

2. **Drive**
   - The main operating mode.
   - Huge map, mission HUD, capture tools.

3. **Leads**
   - Pipeline, follow-ups, lead list, search filters.

4. **Areas**
   - Unified areas, market coverage, missions, street progress.

5. **Command**
   - Business metrics, market health, account, settings, import/data tools.

Global controls:

- Universal search from every tab.
- Account/settings in Command, not as a primary work tab long term.
- Quick Capture floating action when it helps the current screen.

## Screen Redesigns

### Today

Purpose: show the highest ROI actions for today.

Primary sections:

- **Next Best Action**
  - Example: "Drive Owasso North for 42 minutes. 18 high-opportunity streets remain."
  - One primary button: `Start`.

- **Due Today**
  - Calls due.
  - Texts due.
  - Properties to revisit.
  - Overdue follow-ups.

- **Hot Opportunities**
  - Top 5 leads by score and stage.
  - Top 5 revisit properties.
  - Top 3 incomplete areas by opportunity score.

- **Today Route**
  - Planned mission.
  - Estimated time.
  - Expected leads.
  - Start point.

Remove from Today:

- Generic totals that do not suggest action.
- Long lists.
- Raw coverage stats without a recommendation.

### Drive

Purpose: field execution.

Default layout:

- Map occupies nearly the entire screen.
- Top compact HUD:
  - Current area/mission.
  - Coverage percent.
  - Next street.
  - Current speed.
  - GPS/follow status.

- Bottom action bar:
  - Find Me / Following.
  - Add Lead.
  - Photo.
  - Stop/Complete.

Driving state:

- UI collapses automatically.
- Show only:
  - Mission.
  - Next street.
  - Distance/time.
  - Coverage progress.
  - Important property alerts.

Stopped state:

- Bottom sheet expands with:
  - Nearby high-score properties.
  - Skipped properties.
  - Lead capture shortcuts.
  - Route to start.
  - Mission notes.

Drive map layers:

- Covered streets: green.
- Uncovered target streets: red/orange.
- Current route: blue.
- Historical route: muted gray.
- Lead markers: status/score color.
- Target properties: small ranked dots.
- Revisit properties: purple or calendar icon.
- Active next street: bright blue.

### Missions

Purpose: convert "drive this area" into an operating plan.

Mission fields:

- Area.
- Objective.
- Buy box.
- Target property types.
- Target streets.
- Priority score.
- Expected leads.
- Expected ROI.
- Target completion time.
- Start point.
- Recommended route placeholder, then real routing later.

Mission preview:

- One sentence recommendation.
- Estimated time.
- Expected lead count.
- Opportunity score.
- Streets selected.
- Primary action: `Start Mission`.

Mission execution:

- Next street.
- Route progress.
- Covered streets.
- Leads captured.
- Miles driven.
- Time remaining.

Mission recap:

- Miles driven.
- Streets covered.
- Coverage quality.
- Leads added.
- Properties skipped.
- Recommended revisits.
- Next recommended mission.

### Areas

Purpose: one unified operating object. Remove confusion between "Areas" and "Drive Areas."

Area object:

- Name.
- Market/city.
- Owner/team.
- Boundary.
- Coverage history.
- Mission history.
- Lead density.
- Yield score.
- Opportunity score.
- Completion percent.
- Last driven.
- Next recommendation.

Area list:

- Sort by "money next," not creation date.
- Cards show:
  - Name.
  - Completion.
  - Opportunity remaining.
  - Lead yield.
  - Last driven.
  - Next action.

Area detail:

- Coverage map.
- Mission history.
- Target properties.
- Lead yield.
- Revisit queue.
- Data health.
- Buttons:
  - Start recommended mission.
  - Analyze area.
  - Open map.

### Leads

Purpose: work the pipeline without digging.

Lead list:

- Default sort by score and follow-up urgency.
- Quick filters:
  - Hot.
  - Due today.
  - Needs contact.
  - Offer ready.
  - Revisit.

Lead card:

- Address.
- Score.
- Stage.
- Source.
- Next action.
- Last activity.
- MAO / spread if available.

Lead details:

Replace giant text blocks with collapsible cards:

- **Property**
  - Address, year built, sqft, beds/baths, assessed value, ARV, repairs, MAO.

- **Owner**
  - Owner name, mailing address, out-of-state, absentee, portfolio count.

- **Photos**
  - Gallery and photo timeline.

- **Analysis**
  - Score reasons.
  - Distress signals.
  - Suggested next action.

- **Timeline**
  - Created, visited, status changes, notes, photos, offers.

- **Tasks**
  - Call, text, revisit, mail, skip trace.

- **Offers**
  - ARV, repairs, fee, MAO, offer sent.

- **Documents**
  - Mail pieces, skip trace CSVs, contracts later.

### Property Preview / Property Page

Top section:

- Hero photo if available.
- Address.
- Motivation score.
- Lead score.
- Status.

Primary buttons:

- Navigate.
- Call.
- Text.
- Take Photo.
- Add Note.
- Analyze.

Secondary cards:

- Owner.
- Sale history.
- Parcel facts.
- Distress.
- Comps.
- Offers.

### Search

Universal search should cover:

- Address.
- Owner.
- Parcel.
- Tags.
- Notes.
- Phone.
- Mission.
- Area.
- City/market.
- Property type.

Search UI:

- Command palette style.
- Recent searches.
- Result type chips.
- Keyboard-friendly on desktop.

### Command

Purpose: strategy, business metrics, account, and data operations.

Sections:

- KPI dashboard.
- ROI by source.
- Market health.
- Data imports.
- Team/account.
- Export tools.
- Settings.

Move low-frequency controls here:

- Account sign out.
- Data health.
- Import scripts/docs.
- Storage/RLS setup notes.
- Market catalog.

## Workflow Redesigns

### Start Day

Current problem: user has to decide where to go.

New flow:

1. Open app.
2. Today says: "Best action: drive Area X for 45 minutes."
3. Tap Start.
4. Drive opens at current GPS.
5. Mission starts only if GPS is available.

### Create Area

New flow:

1. Drive -> `Create Area`.
2. Draw boundary.
3. Name area.
4. App analyzes streets/properties.
5. Area card shows opportunity score and recommended first mission.

### Start Mission

New flow:

1. Tap recommended mission.
2. Confirm time budget.
3. App gets current location.
4. Saves mission start point.
5. Opens Drive with follow mode on.

### Capture Lead While Driving

New flow:

1. Tap property dot or Quick Capture.
2. One screen:
   - Take photo.
   - Condition tags.
   - Save lead.
3. App fills location, parcel, score, source, mission id automatically.

### Complete Mission

New flow:

1. Tap Complete.
2. App stops GPS.
3. Saves stats.
4. Shows recap.
5. Suggests next action:
   - Follow up with hot lead.
   - Drive next mission.
   - Revisit property.

### Follow Up

New flow:

1. Today shows due actions.
2. Tap action.
3. Lead opens directly to the relevant task card.
4. Completing the task updates timeline and next action.

## Features To Delete Or Hide

Delete or hide from primary screens:

- Raw stats with no recommendation.
- Duplicate Area/Drive Area concepts.
- Giant unstructured notes blocks.
- Multiple map modes that feel like internal implementation terms.
- Manual-only fields during driving.
- Any dashboard card that does not create action.
- Buttons that are disabled without explaining why.

## Features To Combine

- Area and Drive Area -> **Area**.
- Lead Details and Property Preview -> shared **Property Page** pattern.
- Coverage stats and mission stats -> **Progress** component.
- Market Health and Data Imports -> **Command / Data Health**.
- Revisit reminders and follow-up tasks -> **Today**.

## Features To Add

Near term:

- Today page.
- Universal search.
- Collapsible Lead Details cards.
- Next Best Street.
- Route to Start.
- Revisit queue.
- Area yield score.
- Mission recap recommendations.

Mid term:

- Marker clustering.
- Offline queue visibility.
- Background sync status.
- Photo timeline.
- Property change alerts.
- Team assignment.
- Better exports.

Long term:

- Distress detection from photos.
- AI contact strategy.
- AI route planning.
- Real routing engine.
- Comps and ARV enrichment.
- Cash buyer / investor cluster maps.
- Market Memory.

## Technical Improvements

### Flutter Architecture

The app should move away from one large `main.dart`.

Recommended structure:

- `lib/app/`
  - app shell, routing, theme.
- `lib/features/drive/`
  - drive screen, map layers, GPS, missions.
- `lib/features/leads/`
  - list, details, scoring, photos.
- `lib/features/areas/`
  - area list, detail, coverage, analysis.
- `lib/features/today/`
  - next actions and tasks.
- `lib/features/command/`
  - business, settings, data health.
- `lib/data/`
  - Supabase repositories.
- `lib/domain/`
  - pure models and scoring.
- `lib/ui/`
  - shared components.

State management:

- Keep current stateful widgets short term.
- Introduce repositories first.
- Then introduce Riverpod or Bloc for drive state, lead state, and account state.

### Performance

Priorities:

- Lazy load visible map data.
- Avoid fetching every lead/property/street on tab switch.
- Cache stable market and street data.
- Paginate lead lists.
- Cluster map markers.
- Split map layers into dedicated widgets.
- Avoid `setState` over the whole Drive screen on every GPS tick.
- Use throttled GPS map centering.
- Keep GPS stream active only during Drive/mission/tracking.

### Supabase

Priorities:

- Keep RLS on.
- Never use service role key in Flutter.
- Standardize `account_id`, `created_by`, `user_id`.
- Add indexes for:
  - leads account/status/score.
  - leads lat/lng.
  - missions account/area/status.
  - driving_points account/session.
  - city_streets city bounds.
  - street_coverage user/account/street.

### Data Model Direction

Core entities:

- Account.
- User.
- Market.
- Area.
- Mission.
- Property.
- Lead.
- Task.
- Photo.
- Timeline event.
- Coverage segment.

Add timeline events so the app can show history without building a custom audit trail for every table.

## Design System Direction

Visual direction:

- Dark-first Drive Mode.
- Light or adaptive office screens.
- Large field controls.
- Rounded cards.
- Calm neutral backgrounds.
- Strong blue for GPS/action.
- Red/orange only for urgency/opportunity.
- Green only for completed/covered.

Core components:

- Action card.
- Metric pill.
- Score badge.
- Status chip.
- Bottom mission sheet.
- Property card.
- Collapsible section.
- Map floating action cluster.
- Timeline row.
- Empty state with next action.

## ROI-Ranked Roadmap

### Phase 1: Trust And Field Flow

Highest ROI because users will not trust the app if field basics fail.

1. Drive opens at current location.
2. Find Me/follow mode behaves like map apps.
3. Mission start requires and saves GPS start point.
4. Mission completion recap is reliable.
5. Lead photos work every time.
6. Clear login/sign-out/account switching.

### Phase 2: Today Page And Next Actions

1. Create Today tab.
2. Show calls/texts/revisits due.
3. Show recommended drive mission.
4. Show top hot leads.
5. Add one-tap action routing.

### Phase 3: Lead Details Redesign

1. Replace raw text with cards.
2. Add Property, Owner, Photos, Timeline, Tasks, Offers.
3. Collapse advanced sections.
4. Put next action at the top.

### Phase 4: Area Unification

1. Rename Drive Areas to Areas.
2. Area detail becomes the mission/coverage command center.
3. Add yield score and opportunity score.
4. Add mission history and lead density.

### Phase 5: Map Intelligence

1. Next Best Street.
2. Opportunity heatmap.
3. Revisit properties.
4. Marker clustering.
5. Better layer controls.

### Phase 6: Routing

1. Choose routing engine: OSRM, Valhalla, or GraphHopper.
2. Route to mission start.
3. Route through selected mission streets.
4. Optimize missed streets.
5. Cache routes.

### Phase 7: AI Layer

Add only after the data and workflows are reliable.

1. AI lead summary.
2. AI contact strategy.
3. AI revisit recommendation.
4. Photo distress timeline.
5. Offer suggestion.
6. Route planning assistant.

### Phase 8: Team And Scale

1. Team roles.
2. Assign missions.
3. Rep performance.
4. Territory ownership.
5. Manager dashboard.
6. Enterprise exports.

## Mission 2 Recommendation

Mission 2 should be **Today Page + Next Best Action**.

Why:

- It immediately makes the product feel smarter.
- It ties together leads, reminders, missions, and areas.
- It answers the product north-star question.
- It reduces confusion about where to go next.

Minimum Mission 2 scope:

- Add Today tab.
- Show top recommended mission.
- Show overdue/today follow-ups.
- Show hot leads.
- Show one button: `Start Best Mission`.
- Do not add AI yet.
- Use existing data and deterministic rules.

