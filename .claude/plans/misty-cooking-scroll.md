# Plan: Fix Duplicate Banner + Event Details Component

## Context

After implementing the two-stream interrupt architecture, the App Page shows **two redundant banners** for Meeting actions:
1. The **indigo interrupt banner** (Stream 2 — correct, shows "Jump to it" / "Later")
2. The **amber upcoming event banner** (from `getPageData` → `buildUpcomingEvent`) which still shows after the user accepts the interrupt

Additionally, when the current action is a Meeting, the workspace lacks **Event-specific context** (Subject, Description, Location, Start/End Time) that would help the AE prepare.

## Changes

### 1. Suppress duplicate amber banner for Meeting actions

**File:** `force-app/main/default/lwc/nbaDemoAlertBanner/nbaDemoAlertBanner.js`

Modify the `showBanner` getter to hide the amber "Meeting with..." banner when in action mode and the current action is already a Meeting:

```js
get showBanner() {
    if (this.isActionMode && this.currentAction?.actionType === 'Meeting') {
        return false;
    }
    return this.upcomingEvent?.hasUpcoming && !this.dismissed;
}
```

This is safe because:
- The urgency banner already shows "Action due by X" for time-bound actions
- The interrupt banner handles the notification/accept flow
- The amber banner is redundant when the AE already accepted the Meeting interrupt

### 2. Add `eventId` to ActionWrapper

**File:** `force-app/main/default/classes/NbaActionController.cls`

- Add `@AuraEnabled public String eventId;` to `ActionWrapper` class (~line 447)
- In `toWrapperFromRecord()` (~line 333), parse EventId from UniqueKey when actionType is 'Meeting':
  ```apex
  if (action.Action_Type__c == 'Meeting' && action.UniqueKey__c != null) {
      List<String> parts = action.UniqueKey__c.split('\\|');
      if (parts.size() >= 4) {
          w.eventId = parts[3];
      }
  }
  ```
- Add `UniqueKey__c` to the SELECT lists in `checkInterruptsInternal()` (lines 272-288 and 295-310) and `acceptInterrupt()` (line 84-95)

### 3. Create `nbaEventDetails` LWC component

**New files:**
- `force-app/main/default/lwc/nbaEventDetails/nbaEventDetails.js`
- `force-app/main/default/lwc/nbaEventDetails/nbaEventDetails.html`
- `force-app/main/default/lwc/nbaEventDetails/nbaEventDetails.css`
- `force-app/main/default/lwc/nbaEventDetails/nbaEventDetails.js-meta.xml`

**Data fetching:** Use Lightning Data Service (`getRecord`) for 0 Apex SOQL:
```js
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import SUBJECT from '@salesforce/schema/Event.Subject';
import DESCRIPTION from '@salesforce/schema/Event.Description';
import LOCATION from '@salesforce/schema/Event.Location';
import START_DT from '@salesforce/schema/Event.StartDateTime';
import END_DT from '@salesforce/schema/Event.EndDateTime';

@wire(getRecord, { recordId: '$eventId', fields: [SUBJECT, DESCRIPTION, LOCATION, START_DT, END_DT] })
wiredEvent;
```

**API properties:** `@api eventId`

**Display:** A compact card with the Event's meeting info:
- Event Subject (title)
- Start/End time (formatted, e.g. "3:19 PM – 3:49 PM")
- Location (if set)
- Description (if set, truncated with expand)

**Styling:** Reuse the existing design tokens/color variables. Light card with a calendar icon, similar to the insights panel style.

### 4. Wire into workspace

**File:** `force-app/main/default/lwc/nbaDemoWorkspace/nbaDemoWorkspace.html`

Add the event details component between the insights panel and the two-column layout, conditionally shown for Meeting actions:

```html
<!-- Event Details (Meeting actions only) -->
<template lwc:if={showEventDetails}>
    <c-nba-event-details event-id={currentAction.eventId}></c-nba-event-details>
</template>
```

**File:** `force-app/main/default/lwc/nbaDemoWorkspace/nbaDemoWorkspace.js`

Add computed getter:
```js
get showEventDetails() {
    return this.isActionMode
        && this.currentAction?.actionType === 'Meeting'
        && this.currentAction?.eventId;
}
```

## Files Modified

| File | Change |
|------|--------|
| `force-app/main/default/lwc/nbaDemoAlertBanner/nbaDemoAlertBanner.js` | Suppress amber banner for Meeting actions |
| `force-app/main/default/classes/NbaActionController.cls` | Add `eventId` to ActionWrapper, parse from UniqueKey, add UniqueKey to SELECTs |
| `force-app/main/default/lwc/nbaDemoWorkspace/nbaDemoWorkspace.html` | Add `c-nba-event-details` conditional section |
| `force-app/main/default/lwc/nbaDemoWorkspace/nbaDemoWorkspace.js` | Add `showEventDetails` getter |
| **NEW** `force-app/main/default/lwc/nbaEventDetails/*` | New LWC component (4 files: js, html, css, meta.xml) |

## Verification

1. Deploy Apex changes (NbaActionController) → deploy LWC changes
2. Insert a test Event 3 min from now via anonymous Apex
3. Open App Page → verify interrupt banner appears (indigo, "Jump to it")
4. Click "Jump to it" → verify:
   - Amber "Meeting with..." banner is **hidden**
   - Red urgency banner shows countdown
   - New Event Details card appears with Subject, Time, Location, Description
5. Complete the meeting action → verify event details card disappears, next action loads
6. Run targeted tests: `sf apex run test --class-names NbaActionControllerTest --synchronous`
