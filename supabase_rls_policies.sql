-- Row Level Security (RLS) Policies
-- Run this AFTER creating the tables
-- This ensures users can only access data from their assigned branches

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE card_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE online_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE qr_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE dues ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_closings ENABLE ROW LEVEL SECURITY;
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE branch_users ENABLE ROW LEVEL SECURITY;

-- ============================================
-- USERS TABLE POLICIES
-- ============================================
-- Drop existing policies if they exist
DROP POLICY IF EXISTS users_insert_own ON users;
DROP POLICY IF EXISTS users_select_own ON users;
DROP POLICY IF EXISTS users_select_for_owners ON users;
DROP POLICY IF EXISTS users_update_own ON users;

-- Allow users to INSERT their own user record (for registration)
CREATE POLICY users_insert_own ON users
  FOR INSERT
  WITH CHECK (id = auth.uid());

-- Allow users to SELECT their own user record
CREATE POLICY users_select_own ON users
  FOR SELECT
  USING (id = auth.uid());

-- Allow business owners to SELECT users assigned to their branches
CREATE POLICY users_select_for_owners ON users
  FOR SELECT
  USING (
    id IN (
      SELECT user_id FROM branch_users
      WHERE branch_id IN (
        SELECT id FROM branches 
        WHERE business_id IN (
          SELECT id FROM businesses 
          WHERE owner_id = auth.uid()
        )
      )
    )
  );

-- Allow users to UPDATE their own user record
CREATE POLICY users_update_own ON users
  FOR UPDATE
  USING (id = auth.uid());

-- ============================================
-- BUSINESSES TABLE POLICIES
-- ============================================
-- Drop existing policies if they exist
DROP POLICY IF EXISTS businesses_insert_own ON businesses;
DROP POLICY IF EXISTS businesses_select_own ON businesses;
DROP POLICY IF EXISTS businesses_update_own ON businesses;

-- Allow users to INSERT businesses where they are the owner (for registration)
CREATE POLICY businesses_insert_own ON businesses
  FOR INSERT
  WITH CHECK (owner_id = auth.uid());

-- Allow users to SELECT businesses they own
CREATE POLICY businesses_select_own ON businesses
  FOR SELECT
  USING (owner_id = auth.uid());

-- Allow users to UPDATE businesses they own
CREATE POLICY businesses_update_own ON businesses
  FOR UPDATE
  USING (owner_id = auth.uid());

-- ============================================
-- BRANCHES TABLE POLICIES
-- ============================================
-- Drop existing policies if they exist
DROP POLICY IF EXISTS branch_insert_for_owners ON branches;
DROP POLICY IF EXISTS branch_select_access ON branches;
DROP POLICY IF EXISTS branch_select_for_assigned_users ON branches;
DROP POLICY IF EXISTS branch_update_for_owners ON branches;
DROP POLICY IF EXISTS branch_access ON branches;
DROP POLICY IF EXISTS branches_insert_own_business ON branches;
DROP POLICY IF EXISTS branches_update_own ON branches;

-- Drop function if exists
DROP FUNCTION IF EXISTS user_has_branch_access(UUID, UUID);

-- Allow users to INSERT branches if they own the business (for registration)
CREATE POLICY branch_insert_for_owners ON branches
  FOR INSERT
  WITH CHECK (
    business_id IN (
      SELECT id FROM businesses 
      WHERE owner_id = auth.uid()
    )
  );

-- Allow business owners to SELECT branches for their businesses
CREATE POLICY branch_select_access ON branches
  FOR SELECT
  USING (
    business_id IN (
      SELECT id FROM businesses 
      WHERE owner_id = auth.uid()
    )
  );

-- Create a function to check if user is assigned to branch (avoids recursion)
CREATE OR REPLACE FUNCTION user_has_branch_access(branch_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_id = branch_uuid 
    AND user_id = user_uuid
  );
END;
$$;

-- Allow users to SELECT branches they're assigned to (using function to avoid recursion)
CREATE POLICY branch_select_for_assigned_users ON branches
  FOR SELECT
  USING (user_has_branch_access(id, auth.uid()));

-- Allow users to UPDATE branches if they own the business
CREATE POLICY branch_update_for_owners ON branches
  FOR UPDATE
  USING (
    business_id IN (
      SELECT id FROM businesses 
      WHERE owner_id = auth.uid()
    )
  );

-- ============================================
-- BRANCH_USERS TABLE POLICIES
-- ============================================
-- Drop existing policies if they exist
DROP POLICY IF EXISTS branch_user_insert_for_owners ON branch_users;
DROP POLICY IF EXISTS branch_user_select ON branch_users;
DROP POLICY IF EXISTS branch_user_select_for_owners ON branch_users;
DROP POLICY IF EXISTS branch_user_update_for_owners ON branch_users;
DROP POLICY IF EXISTS branch_user_view ON branch_users;
DROP POLICY IF EXISTS branch_users_insert_own_branch ON branch_users;

-- Allow users to INSERT into branch_users if they own the business OR are assigning themselves
CREATE POLICY branch_user_insert_for_owners ON branch_users
  FOR INSERT
  WITH CHECK (
    branch_id IN (
      SELECT id FROM branches 
      WHERE business_id IN (
        SELECT id FROM businesses 
        WHERE owner_id = auth.uid()
      )
    )
    OR
    user_id = auth.uid()
  );

-- Allow users to SELECT their own branch assignments
CREATE POLICY branch_user_select ON branch_users
  FOR SELECT
  USING (user_id = auth.uid());

-- Allow business owners to SELECT branch_users for their branches
CREATE POLICY branch_user_select_for_owners ON branch_users
  FOR SELECT
  USING (
    branch_id IN (
      SELECT id FROM branches 
      WHERE business_id IN (
        SELECT id FROM businesses 
        WHERE owner_id = auth.uid()
      )
    )
  );

-- Allow users to UPDATE branch_users if they own the business
CREATE POLICY branch_user_update_for_owners ON branch_users
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

-- ============================================
-- DATA TABLES POLICIES (Cash Expenses, Sales, etc.)
-- ============================================
-- Drop existing policies if they exist
DROP POLICY IF EXISTS branch_user_access ON cash_expenses;
DROP POLICY IF EXISTS branch_user_access ON cash_counts;
DROP POLICY IF EXISTS branch_user_access ON card_sales;
DROP POLICY IF EXISTS branch_user_access ON online_sales;
DROP POLICY IF EXISTS branch_user_access ON qr_payments;
DROP POLICY IF EXISTS branch_user_access ON dues;
DROP POLICY IF EXISTS branch_user_access ON cash_closings;

-- Policy: Users can only access data from their assigned branches
CREATE POLICY branch_user_access ON cash_expenses
  FOR ALL
  USING (
    branch_id IN (
      SELECT branch_id FROM branch_users 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY branch_user_access ON cash_counts
  FOR ALL
  USING (
    branch_id IN (
      SELECT branch_id FROM branch_users 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY branch_user_access ON card_sales
  FOR ALL
  USING (
    branch_id IN (
      SELECT branch_id FROM branch_users 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY branch_user_access ON online_sales
  FOR ALL
  USING (
    branch_id IN (
      SELECT branch_id FROM branch_users 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY branch_user_access ON qr_payments
  FOR ALL
  USING (
    branch_id IN (
      SELECT branch_id FROM branch_users 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY branch_user_access ON dues
  FOR ALL
  USING (
    branch_id IN (
      SELECT branch_id FROM branch_users 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY branch_user_access ON cash_closings
  FOR ALL
  USING (
    branch_id IN (
      SELECT branch_id FROM branch_users 
      WHERE user_id = auth.uid()
    )
  );

