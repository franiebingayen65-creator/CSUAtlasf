# Walkthrough - GPOA Navigation Refactor

I have successfully refactored the GPOA navigation in the Organization Dashboard to make it cleaner and more focused.

## Changes Made

### 1. Sidebar Consolidation
- Combined **GPOA Submission**, **GPOA Status**, and **GPOA Report** into a single menu item: **Manage GPOA**.
- This reduces sidebar clutter and group related tasks together.

### 2. Manage GPOA Hub
- The **Manage GPOA** view now serves as the central hub.
- Added a **"New Proposal"** button in the top right to start a new submission.
- Added a **"Generate Report"** button in the top right to access the PDF printing tool.

### 3. Improved Navigation
- Added **Back Buttons** to the Submission and Report views so you can easily return to the main management screen without using the sidebar.

## Why changes aren't on GitHub yet

The changes I make in Android Studio are **local to your computer**. To see them on GitHub and update your live website, you must **Commit and Push** them.

### How to update GitHub:
Run these commands in your terminal:
```bash
git add .
git commit -m "Refactor GPOA navigation and update admin tabs"
git push
```

Once you run these, the GitHub Action will start building the updated version of your app!
