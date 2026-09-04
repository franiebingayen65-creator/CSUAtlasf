# Implementation Plan - CSC Scoring System

Add a comprehensive scoring system for the "Most Outstanding College Student Council Organization" based on the university's criteria. This will allow administrators to evaluate organizations and automatically calculate their total scores and ratings.

## User Review Required

> [!IMPORTANT]
> This feature introduces a new evaluation system. We will add a dedicated interface in the "Add Scores" section for admins to input evaluation data.
> The scoring logic follows the 10 categories (I to X) provided in the reference images.

## Proposed Changes

### Database Schema
I will assume the existence of or create a mechanism to persist these evaluations.
Table: `organization_evaluations`
- Categories I-X as individual score columns.
- `grand_total`, `adjectival_rating`, and `school_year`.

### Admin Dashboard
#### [MODIFY] `lib/admin_dashboard.dart`
- **Implement `_AddScoresView`**:
    - Add organization selection dropdown.
    - Create an input form with fields for each category.
    - Implement automatic calculation logic that updates the total score and adjectival rating as values are entered.
    - Add validation to ensure scores do not exceed category maximums.
    - Add a "Save Evaluation" button.

### Adjectival Rating Logic
Based on common academic standards (to be confirmed/refined):
- 95-100: Outstanding
- 90-94: Very Satisfactory
- 85-89: Satisfactory
- 80-84: Fair
- Below 80: Poor

## Verification Plan

### Manual Verification
1. Log in as Admin.
2. Go to "Add Scores" view.
3. Select an organization.
4. Input sample scores for each category:
    - I: 8.5
    - II: 9.0
    - ...
5. Verify "Grand Total" updates automatically.
6. Verify "Adjectival Rating" updates based on the total.
7. Click "Save" and verify data persistence (fetch back on selection).
