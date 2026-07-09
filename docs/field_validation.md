# Market Coverage OS Field Validation Checklist

Use this checklist when testing a fresh iPhone build in the field.

The goal is not to test everything in the app. The goal is to confirm the field-critical bugs and move journal items from "fix pushed, awaiting user confirmation" to either "confirmed fixed" or "reopened with evidence."

## Before You Drive

1. Pull and run the latest build on the Mac:

   ```bash
   mco
   ```

2. Open the app on iPhone.
3. Go to Settings.
4. Tap `Copy Build Info`.
5. Paste the build info into your notes before testing.

Required report header:

```text
Build info:
<paste Settings > Build Identity here>

Tester:
Date:
Market:
Area:
Weather / driving context:
```

## Test Result Labels

Use one label for every item:

- `PASS`: works correctly on this build.
- `FAIL`: does not work correctly on this build.
- `BLOCKED`: could not test because setup/data/location made it impossible.
- `UNCLEAR`: behavior happened but the expected result is not obvious.

For every `FAIL` or `UNCLEAR`, record:

- What screen you were on.
- What you tapped.
- What happened.
- Screenshot or short video if possible.
- Whether restarting the app changed the result.

## 1. Startup And Location

Purpose: confirm the app can start a driving session from real location without freezing.

Checklist:

- [ ] Drive tab opens without hanging.
- [ ] Current location appears on the map.
- [ ] Find Me/Following button changes state visibly when tapped.
- [ ] Follow mode actually follows while driving, not just says "Following."
- [ ] User marker updates smoothly while moving.
- [ ] App does not freeze when the GPS marker changes from dot to arrow.
- [ ] Sitting still for 2 minutes does not draw a fake blue route line from GPS drift.

Notes:

```text
Startup/location result:
```

## 2. Mission Start

Purpose: confirm mission entry is understandable and does not require unrelated actions.

Checklist:

- [ ] Active area is clear before starting.
- [ ] Start Mission is available only when the area has usable street data.
- [ ] Mission start does not require tapping "Find Motivated Sellers."
- [ ] Mission starts only after current location is available.
- [ ] Mission start point is saved.
- [ ] Mission preview estimates are believable for the area.

Notes:

```text
Mission start result:
```

## 3. Live Mission Tracking

Purpose: confirm live mission stats reflect the real drive.

Checklist:

- [ ] Time taken increases during the mission.
- [ ] Route line follows the actual driven path.
- [ ] Streets covered count increases as streets are driven.
- [ ] Covered streets turn green after driving them.
- [ ] Undriven streets stay red.
- [ ] Mission percent is mathematically believable. Example: 1 of 2 streets should show 50%, not 0%.
- [ ] App stays responsive while parcels and street lines are visible.

Notes:

```text
Live mission result:
```

## 4. Lead Capture While Driving

Purpose: confirm the app can capture a lead quickly during a mission.

Checklist:

- [ ] Quick Capture opens from the orange button.
- [ ] Saving a lead without a photo still works.
- [ ] Adding a photo still works.
- [ ] GPS is saved on the lead.
- [ ] Address is filled when reverse geocoding succeeds.
- [ ] If no parcel data exists, lead capture is still allowed.
- [ ] Quick Capture closes cleanly after saving.
- [ ] Captured mission lead appears in Leads.
- [ ] Captured mission lead appears on the map.

Notes:

```text
Lead capture result:
```

## 5. Mission Completion

Purpose: confirm completion flow is clean and recap numbers match the mission.

Checklist:

- [ ] Complete Mission is available only while a mission is active.
- [ ] Completing mission stops GPS tracking.
- [ ] Recap opens automatically.
- [ ] Recap time taken matches the drive.
- [ ] Recap streets covered matches the live mission.
- [ ] Recap leads captured matches leads added during the mission.
- [ ] Recap miles/leads-per-mile are not impossible or misleading.
- [ ] Done closes the recap and returns to the correct Drive state.

Notes:

```text
Mission completion result:
```

## 6. Area And Coverage Persistence

Purpose: confirm the app remembers coverage after the mission.

Checklist:

- [ ] Area stats show streets driven / total streets correctly.
- [ ] Area stats show miles covered / total miles correctly.
- [ ] Coverage percent matches the street count. Example: 9 of 158 should not show 0%.
- [ ] Closing and reopening the app preserves covered streets.
- [ ] Completed streets remain green after restart.
- [ ] Historical route remains visible if expected for that screen.

Notes:

```text
Coverage persistence result:
```

## 7. Map Layer Visibility

Purpose: confirm the map remains usable with real data visible.

Checklist:

- [ ] Owasso streets show correctly.
- [ ] Tulsa streets show where imported.
- [ ] Parcels can be shown when available.
- [ ] Street lines can be shown when available.
- [ ] Parcel boundaries are readable on Satellite.
- [ ] Parcel boundaries are readable on Dark.
- [ ] Parcel boundaries are readable on Minimal.
- [ ] Lead markers remain visible above streets/parcels.
- [ ] House-number labels do not overwhelm the map at normal driving zoom.

Notes:

```text
Map layer result:
```

## 8. Quick Non-Driving Regression Checks

Run these before or after the real drive.

Checklist:

- [ ] Today shows overdue/due-today tasks.
- [ ] Tapping a Today task opens the attached lead.
- [ ] Completing a task inline removes it from Today.
- [ ] Lead deletion works from Lead Details.
- [ ] Lead deletion works from the Leads tab if that action is visible.
- [ ] Lead Details does not overflow on iPhone.
- [ ] Property Preview close button is visible and sticky.
- [ ] Lead Details close button is visible and sticky.

Notes:

```text
Regression result:
```

## Copy/Paste Report Template

Use this when sending results back to Codex:

```text
FIELD1 report

Build info:

Tester:
Date:
Market:
Area:

1. Startup And Location:
PASS/FAIL/BLOCKED/UNCLEAR
Notes:

2. Mission Start:
PASS/FAIL/BLOCKED/UNCLEAR
Notes:

3. Live Mission Tracking:
PASS/FAIL/BLOCKED/UNCLEAR
Notes:

4. Lead Capture While Driving:
PASS/FAIL/BLOCKED/UNCLEAR
Notes:

5. Mission Completion:
PASS/FAIL/BLOCKED/UNCLEAR
Notes:

6. Area And Coverage Persistence:
PASS/FAIL/BLOCKED/UNCLEAR
Notes:

7. Map Layer Visibility:
PASS/FAIL/BLOCKED/UNCLEAR
Notes:

8. Quick Non-Driving Regression Checks:
PASS/FAIL/BLOCKED/UNCLEAR
Notes:

Screenshots/videos attached:
```

## How Codex Should Use Results

After the user sends a FIELD1 report:

1. Move passed items from `Fix pushed, awaiting user confirmation` to `Fixed And Confirmed By User`.
2. Keep failed items in `Current Known Issues To Watch`.
3. If a failed item has a clear root cause and matches the task queue, make it the next fix.
4. Record the build hash with every confirmation or reopened bug.
5. Do not start a new feature slice while high-priority field failures are still untriaged.
