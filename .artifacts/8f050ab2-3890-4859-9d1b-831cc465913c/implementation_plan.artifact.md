# Implementation Plan - PDF Compatibility & GitHub Automation

This plan covers two major improvements:
1. **PDF Compatibility**: Ensuring PDFs render correctly on all devices by embedding fonts.
2. **GitHub Integration**: Setting up Version Control and an Automated Workflow (CI/CD) so your web version updates automatically whenever you push code.

## User Review Required

> [!IMPORTANT]
> **GitHub Secrets:** To automate the web build securely, I will set up a GitHub Action. If you have sensitive keys (like Supabase Service Role keys, though your current ones are public anon keys), we should move them to GitHub Secrets later.
>
> **GitHub Pages:** This plan assumes you want to use **GitHub Pages** to host your web app for free. Every time you `git push`, GitHub will rebuild the web app and update the live link.

## Proposed Changes

### 1. PDF Utility Component
#### [MODIFY] [pdf_generator.dart](file:///C:/CSUAtlasf/lib/utils/pdf_generator.dart)
- Embed **Roboto** font family using `PdfGoogleFonts`.
- Apply the embedded fonts to all text styles in the document.

### 2. GitHub & Automation Setup
#### [NEW] [.github/workflows/deploy.yml](file:///C:/CSUAtlasf/.github/workflows/deploy.yml)
- Create a workflow that:
  - Triggers on every push to the `main` branch.
  - Installs Flutter.
  - Builds the Flutter Web app.
  - Deploys the build output to the `gh-pages` branch.

#### [LOCAL] Git Initialization
- Run `git init` locally.
- Create initial commit.

## Open Questions
- Do you already have a GitHub repository created, or should I provide the commands to link it once you create one?
- Are you okay with using GitHub Pages for the "auto-updating" web version?

## Verification Plan

### Manual Verification
1. **GitHub Action**: After pushing, check the "Actions" tab on GitHub to see the build progress.
2. **Web Link**: Once the action finishes, visit `https://<your-username>.github.io/<repo-name>/` to see your updated app.
3. **PDF Test**: Generate a PDF from the live web version and verify font embedding.
