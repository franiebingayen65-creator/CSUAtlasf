-- Add reaccreditation_is_archived column to organizations table
-- Used by the "Reset All (New School Year)" flow to archive re-accreditation
-- submissions while keeping the data restorable.
ALTER TABLE organizations
  ADD COLUMN IF NOT EXISTS reaccreditation_is_archived boolean NOT NULL DEFAULT false;
