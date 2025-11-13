-- Migration: Add branch_id to card_machines and enable RLS
-- Run this in Supabase SQL Editor

-- Step 1: Add branch_id column to card_machines
ALTER TABLE card_machines
ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES branches(id) ON DELETE CASCADE;

-- Step 2: Create index for performance
CREATE INDEX IF NOT EXISTS idx_card_machines_branch ON card_machines(branch_id);

-- Step 3: Enable RLS on card_machines
ALTER TABLE card_machines ENABLE ROW LEVEL SECURITY;

-- Step 4: Drop existing policies if they exist
DROP POLICY IF EXISTS card_machines_select_for_branch ON card_machines;
DROP POLICY IF EXISTS card_machines_insert_for_owners ON card_machines;
DROP POLICY IF EXISTS card_machines_update_for_owners ON card_machines;
DROP POLICY IF EXISTS card_machines_delete_for_owners ON card_machines;

-- Step 5: Create RLS policies

-- Allow users to SELECT card machines for their assigned branches
CREATE POLICY card_machines_select_for_branch ON card_machines
  FOR SELECT
  USING (
    branch_id IN (
      SELECT branch_id FROM branch_users
      WHERE user_id = auth.uid()
    )
    OR
    branch_id IN (
      SELECT id FROM branches
      WHERE business_id IN (
        SELECT id FROM businesses
        WHERE owner_id = auth.uid()
      )
    )
  );

-- Allow business owners to INSERT card machines for their branches
CREATE POLICY card_machines_insert_for_owners ON card_machines
  FOR INSERT
  WITH CHECK (
    branch_id IN (
      SELECT id FROM branches
      WHERE business_id IN (
        SELECT id FROM businesses
        WHERE owner_id = auth.uid()
      )
    )
  );

-- Allow business owners to UPDATE card machines for their branches
CREATE POLICY card_machines_update_for_owners ON card_machines
  FOR UPDATE
  USING (
    branch_id IN (
      SELECT id FROM branches
      WHERE business_id IN (
        SELECT id FROM businesses
        WHERE owner_id = auth.uid()
      )
    )
  );

-- Allow business owners to DELETE card machines for their branches
CREATE POLICY card_machines_delete_for_owners ON card_machines
  FOR DELETE
  USING (
    branch_id IN (
      SELECT id FROM branches
      WHERE business_id IN (
        SELECT id FROM businesses
        WHERE owner_id = auth.uid()
      )
    )
  );

