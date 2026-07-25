# Implementation Plan - Refactor GPOA Navigation

The goal is to consolidate the three GPOA-related navigation items ("GPOA Submission", "GPOA Status", "GPOA Report") into a single sidebar item named **"Manage GPOA"**. Access to submission and reporting will be moved to buttons in the top-right corner of the management view.

## User Review Required

> [!IMPORTANT]
> The sidebar will now only show "Manage GPOA" instead of three separate items.
> Clicking the "GPOA Submission" or "GPOA Report" buttons in the top right will navigate you to those specific forms/views.
> I will add a "Back" button to those views so you can easily return to the main "Manage GPOA" status screen.

## Proposed Changes

### Organization Dashboard Navigation

#### [MODIFY] [org_dashboard.dart](file:///C:/CSUAtlasf/lib/org_dashboard.dart)
- **Sidebar**:
    - Remove "GPOA Submission" and "GPOA Report" items.
    - Rename "GPOA Status" to "Manage GPOA".
    - Update selection logic so "Manage GPOA" remains highlighted when on the submission or report pages.
- **Main Content**:
    - Update `_GPOAStatusGridView` to include two buttons in the top right: "New Proposal" (links to Submission) and "Generate Report" (links to Report).
    - Add a "Back" button to `_GPOASubmissionView` and `_GPOAReportPrintingView` to facilitate returning to the status grid.
    - Rename internal references from "Status" to "Manage GPOA" where appropriate for consistency.

## Verification Plan

### Manual Verification
1. Open the Organization Dashboard.
2. Verify the sidebar only has "Manage GPOA" under GPOA MANAGEMENT.
3. Click "Manage GPOA" and verify the Status Grid is shown.
4. Click the "New Proposal" button in the top right and verify it opens the submission form.
5. Verify the sidebar still highlights "Manage GPOA".
6. Click the "Back" button in the submission form and verify it returns to the status grid.
7. Repeat the same for the "Generate Report" button.
