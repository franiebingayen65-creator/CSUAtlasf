# Implementation Plan - Activity Workflow UI Cleanup

The goal is to simplify the "View Events" page in the Organization Dashboard by removing the "Phase" terminology and providing more professional titles.

## Proposed Changes

### Organization Dashboard

#### [MODIFY] [org_dashboard.dart](file:///C:/CSUAtlasf/lib/org_dashboard.dart)
- Update the main title and description of the `_OrgViewEventsView`.
- Remove "Phase X:" prefixes from the TabBar items.
- Update tab names to be more descriptive:
    - "Phase 1: Scheduling" -> "For Scheduling"
    - "Phase 2: Review" -> "Awaiting Approval"
    - "Phase 3: Ongoing" -> "Ongoing Events"
    - "Phase 4: Completed" -> "Completed"

## Verification Plan

### Manual Verification
1. Log in as a President or Adviser.
2. Navigate to "View Events" in the sidebar.
3. Verify the main header says "Activity Progress Tracker".
4. Verify the tabs no longer show "Phase 1", "Phase 2", etc.
5. Verify the tab content still displays the correct activity lists.
