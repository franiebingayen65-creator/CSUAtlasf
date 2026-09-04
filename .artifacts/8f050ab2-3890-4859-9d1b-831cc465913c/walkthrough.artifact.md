# Walkthrough - CSC Scoring & Ranking System

I have implemented the complete scoring system for the "Most Outstanding College Student Council Organization" evaluation.

## Key Features

### 1. New Evaluation Interface
- Added a professional scoring form in the **"Add Scores"** section of the Admin Dashboard.
- Support for **School Year** selection (e.g., SY 2025-2026).
- Real-time automatic calculation of the **Grand Total** and **Adjectival Rating** as scores are entered.

### 2. Scoring Categories
- Implemented all 10 categories from the university criteria:
    - **I - VI**: Activity-based scores (max 10/5 pts).
    - **VII**: Tangible/Physical Projects (max 15 pts).
    - **VIII - IX**: Financial-based scores (max 10 pts).
    - **X**: Implementation percentage (max 10 pts).
- Built-in validation ensures scores do not exceed their category maximums.

### 3. Leaderboard & Rankings
- Implemented the **"View Ranks"** section.
- Organizations are automatically ranked based on their Grand Total.
- The ranking list displays the organizational name, adjectival rating, and total points.

### 4. Data Persistence
- Evaluations are saved to Supabase and can be loaded/edited later by selecting the same organization and school year.

## Technical Details
- Modified `lib/admin_dashboard.dart` to replace placeholder views with functional components.
- Added logic for adjectival rating calculation:
    - `Outstanding` (96-100)
    - `Very Satisfactory` (86-95)
    - `Satisfactory` (76-85)
    - `Fair` (66-75)
    - `Poor` (Below 66)

## Verification
- Select an organization in "Add Scores".
- Enter values for Categories I to X.
- Observe the Summary card updating instantly.
- Click "Save Evaluation".
- Switch to "View Ranks" to see the organization appear in the leaderboard.
