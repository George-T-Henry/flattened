-- Migration: Add label column to flattened_profiles table
-- This adds support for storing labels from public_profiles.label

-- Add label column to flattened_profiles table
ALTER TABLE flattened_profiles 
ADD COLUMN IF NOT EXISTS label TEXT;

-- Create index on label for better query performance
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_label 
ON flattened_profiles (label);

-- Update the table comment to reflect the new column
COMMENT ON COLUMN flattened_profiles.label IS 'Label from public_profiles table for organizing profile batches';