# Implementation Plan - Refine Scheduling Revisions

The goal is to simplify the revision process within the "Scheduling & Letters" navigation by introducing a dedicated "Revisions" tab and limiting corrections to only the event schedule (date/time).

## Proposed Changes

### Organization Dashboard

#### [MODIFY] [org_dashboard.dart](file:///C:/CSUAtlasf/lib/org_dashboard.dart)
- Update `_MyEventsView` to use **three tabs**:
    1.  **"Event Scheduling"**: For activities with status `Approved` or `Awaiting Date Approval`.
    2.  **"Activity Corrections"**: For activities with status `Needs Revision`.
    3.  **"Request Letters"**: For activities with status `Scheduled`.
- Modify the "Revise" action for items in the **Activity Corrections** tab:
    - Instead of allowing full text edits, it will open the **Date and Time picker**.
    - After picking a new date, the activity will be resubmitted with the status set back to `Awaiting Date Approval`.
- Update internal filtering logic (`schedulingList`, `revisionList`, `letterList`) to support the new three-tab layout.

## Verification Plan

### Manual Verification
1.  Navigate to "Scheduling & Letters".
2.  Verify there are now **three tabs** at the top.
3.  Ensure items with status `Needs Revision` appear in the "Activity Corrections" tab.
4.  Click the "Revise" button on an item in the corrections tab.
5.  Verify that it only prompts for a **Date and Time**, not a full form.
6.  Confirm that after saving, the item moves to the "Event Scheduling" tab with a "Pending" or "Awaiting Approval" label.
7.  Verify that the "Request Letters" tab remains isolated for `Scheduled` activities.
