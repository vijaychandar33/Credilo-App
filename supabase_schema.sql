-- credilo - Database Schema (reference)
-- Matches production. Migrations are applied via Supabase; this file is the single source of truth.

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Businesses table
CREATE TABLE businesses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Branches table
CREATE TABLE branches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  business_id UUID REFERENCES businesses(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  location TEXT NOT NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security on branches table
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;

-- Helper function to check if user has branch access (prevents infinite recursion in RLS)
CREATE OR REPLACE FUNCTION check_user_has_branch_access(p_business_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- This function bypasses RLS, so it won't trigger recursion
  RETURN EXISTS (
    SELECT 1 FROM branch_users
    WHERE business_id = p_business_id
    AND user_id = p_user_id
  );
END;
$$;

-- Helper function to get current user's email (for RLS policies)
CREATE OR REPLACE FUNCTION get_current_user_email()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_email text;
BEGIN
  SELECT email INTO v_email
  FROM auth.users
  WHERE id = auth.uid();
  RETURN v_email;
END;
$$;

-- Helper function to check if user has pending invitation
CREATE OR REPLACE FUNCTION check_user_has_pending_invitation(p_business_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_email text;
BEGIN
  -- Get the authenticated user's email
  v_user_email := get_current_user_email();
  
  -- Check if there's a pending_users record for this email and business
  RETURN EXISTS (
    SELECT 1 FROM pending_users
    WHERE business_id = p_business_id
    AND email = v_user_email
  );
END;
$$;

-- RLS Policy: Allow users to read branches if they have a branch_users record for that business
CREATE POLICY "Users can read branches for their businesses"
ON branches
FOR SELECT
USING (
  check_user_has_branch_access(branches.business_id, auth.uid())
);

-- RLS Policy: Allow authenticated users to read branches if they have a pending_users record for that business
-- This is needed during account creation when the user logs in via OTP
CREATE POLICY "Users can read branches if they have pending invitation"
ON branches
FOR SELECT
USING (
  auth.uid() IS NOT NULL
  AND check_user_has_pending_invitation(branches.business_id)
);

-- RLS Policy: Allow users to update branches for their businesses (name, location, status)
CREATE POLICY "Users can update branches for their businesses"
ON branches
FOR UPDATE
USING (check_user_has_branch_access(branches.business_id, auth.uid()))
WITH CHECK (check_user_has_branch_access(branches.business_id, auth.uid()));

-- RLS Policy: Allow users to insert branches for their businesses (e.g. business owners adding branches)
CREATE POLICY "Users can insert branches for their businesses"
ON branches
FOR INSERT
WITH CHECK (check_user_has_branch_access(branches.business_id, auth.uid()));

-- Branch visibility (what to show on home screen per branch; UI only, default visible)
CREATE TABLE branch_visibility (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  item_key TEXT NOT NULL,
  visible BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(branch_id, item_key)
);
CREATE INDEX idx_branch_visibility_branch_id ON branch_visibility(branch_id);
ALTER TABLE branch_visibility ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read branch_visibility for their branches" ON branch_visibility FOR SELECT USING (
  EXISTS (SELECT 1 FROM branch_users WHERE branch_users.branch_id = branch_visibility.branch_id AND branch_users.user_id = auth.uid())
);
CREATE POLICY "Users can insert branch_visibility for their branches" ON branch_visibility FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM branch_users WHERE branch_users.branch_id = branch_visibility.branch_id AND branch_users.user_id = auth.uid())
);
CREATE POLICY "Users can update branch_visibility for their branches" ON branch_visibility FOR UPDATE USING (
  EXISTS (SELECT 1 FROM branch_users WHERE branch_users.branch_id = branch_visibility.branch_id AND branch_users.user_id = auth.uid())
) WITH CHECK (
  EXISTS (SELECT 1 FROM branch_users WHERE branch_users.branch_id = branch_visibility.branch_id AND branch_users.user_id = auth.uid())
);
CREATE POLICY "Users can delete branch_visibility for their branches" ON branch_visibility FOR DELETE USING (
  EXISTS (SELECT 1 FROM branch_users WHERE branch_users.branch_id = branch_visibility.branch_id AND branch_users.user_id = auth.uid())
);

-- Branch closing cycle (per-branch custom closing time; replaces device-level setting)
CREATE TABLE branch_closing_cycle (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  use_custom_closing BOOLEAN NOT NULL DEFAULT false,
  closing_hour INT NOT NULL DEFAULT 1,
  closing_minute INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(branch_id),
  CHECK (closing_hour >= 0 AND closing_hour <= 23),
  CHECK (closing_minute >= 0 AND closing_minute <= 59)
);
CREATE INDEX idx_branch_closing_cycle_branch_id ON branch_closing_cycle(branch_id);
ALTER TABLE branch_closing_cycle ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read branch_closing_cycle for their branches" ON branch_closing_cycle FOR SELECT USING (
  EXISTS (SELECT 1 FROM branch_users WHERE branch_users.branch_id = branch_closing_cycle.branch_id AND branch_users.user_id = auth.uid())
);
CREATE POLICY "Users can insert branch_closing_cycle for their branches" ON branch_closing_cycle FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM branch_users WHERE branch_users.branch_id = branch_closing_cycle.branch_id AND branch_users.user_id = auth.uid())
);
CREATE POLICY "Users can update branch_closing_cycle for their branches" ON branch_closing_cycle FOR UPDATE USING (
  EXISTS (SELECT 1 FROM branch_users WHERE branch_users.branch_id = branch_closing_cycle.branch_id AND branch_users.user_id = auth.uid())
) WITH CHECK (
  EXISTS (SELECT 1 FROM branch_users WHERE branch_users.branch_id = branch_closing_cycle.branch_id AND branch_users.user_id = auth.uid())
);

-- Branch users (junction table for user-branch-role)
CREATE TABLE branch_users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('business_owner', 'business_owner_read_only', 'owner', 'owner_read_only', 'manager', 'staff')),
  permissions JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(branch_id, user_id)
);

-- Pending users table (for storing user invitations before account creation)
CREATE TABLE pending_users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  phone TEXT,
  role TEXT NOT NULL CHECK (role IN ('business_owner', 'business_owner_read_only', 'owner', 'owner_read_only', 'manager', 'staff')),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security on pending_users table
ALTER TABLE pending_users ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Allow business owners/managers to read pending_users for their businesses
CREATE POLICY "Business owners can read pending users for their businesses"
ON pending_users
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.business_id = pending_users.business_id
    AND branch_users.user_id = auth.uid()
    AND branch_users.role IN ('business_owner', 'business_owner_read_only', 'owner', 'manager')
  )
);

-- RLS Policy: Allow authenticated users to read their own pending invitation (by email)
-- Uses get_current_user_email() function to avoid RLS issues with auth.users table
CREATE POLICY "Users can read their own pending invitation"
ON pending_users
FOR SELECT
USING (
  auth.uid() IS NOT NULL
  AND pending_users.email = get_current_user_email()
);

-- RLS Policy: Allow business owners/managers to insert pending_users for their businesses
CREATE POLICY "Business owners can insert pending users"
ON pending_users
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.business_id = pending_users.business_id
    AND branch_users.user_id = auth.uid()
    AND branch_users.role IN ('business_owner', 'business_owner_read_only', 'owner', 'manager')
  )
);

-- RLS Policy: Allow business owners/managers to delete pending_users for their businesses
CREATE POLICY "Business owners can delete pending users"
ON pending_users
FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.business_id = pending_users.business_id
    AND branch_users.user_id = auth.uid()
    AND branch_users.role IN ('business_owner', 'business_owner_read_only', 'owner', 'manager')
  )
);

-- Cash expenses
CREATE TABLE cash_expenses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  user_id UUID REFERENCES users(id),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  item TEXT NOT NULL,
  category TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  note TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Online expenses (for UPI/bank transfer payments)
CREATE TABLE online_expenses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  user_id UUID REFERENCES users(id),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  item TEXT NOT NULL,
  category TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  note TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Suppliers
CREATE TABLE suppliers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  business_id UUID REFERENCES businesses(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  contact TEXT,
  address TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Credit expenses
CREATE TABLE credit_expenses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  user_id UUID REFERENCES users(id),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  supplier TEXT NOT NULL,
  category TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  note TEXT,
  status TEXT DEFAULT 'unpaid' CHECK (status IN ('paid', 'unpaid')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Cash counts
CREATE TABLE cash_counts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  user_id UUID REFERENCES users(id),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  denomination TEXT NOT NULL,
  count INTEGER NOT NULL,
  total NUMERIC(12,2) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Card sales
CREATE TABLE card_sales (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  user_id UUID REFERENCES users(id),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  tid TEXT NOT NULL,
  machine_name TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Card machines
CREATE TABLE card_machines (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  tid TEXT NOT NULL,
  location TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Online sales
CREATE TABLE online_sales (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  user_id UUID REFERENCES users(id),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  platform TEXT NOT NULL,
  gross NUMERIC(12,2) NOT NULL,
  commission NUMERIC(12,2),
  net NUMERIC(12,2) NOT NULL,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- QR payments
CREATE TABLE qr_payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  user_id UUID REFERENCES users(id),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  amount NUMERIC(12,2),
  amount_before_midnight NUMERIC(12,2),
  amount_after_midnight NUMERIC(12,2),
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Daily QR payment totals (stores calculated total per day per branch)
CREATE TABLE daily_qr_totals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  calculated_total NUMERIC(12,2) NOT NULL DEFAULT 0,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(date, branch_id)
);

-- Enable Row Level Security on daily_qr_totals
ALTER TABLE daily_qr_totals ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read daily_qr_totals for branches they have access to
CREATE POLICY "Users can read daily_qr_totals for their branches"
ON daily_qr_totals
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = daily_qr_totals.branch_id
    AND branch_users.user_id = auth.uid()
  )
);

-- Policy: Users can insert daily_qr_totals for branches they have access to
CREATE POLICY "Users can insert daily_qr_totals for their branches"
ON daily_qr_totals
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = daily_qr_totals.branch_id
    AND branch_users.user_id = auth.uid()
  )
);

-- Policy: Users can update daily_qr_totals for branches they have access to
CREATE POLICY "Users can update daily_qr_totals for their branches"
ON daily_qr_totals
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = daily_qr_totals.branch_id
    AND branch_users.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = daily_qr_totals.branch_id
    AND branch_users.user_id = auth.uid()
  )
);

-- Policy: Users can delete daily_qr_totals for branches they have access to
CREATE POLICY "Users can delete daily_qr_totals for their branches"
ON daily_qr_totals
FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = daily_qr_totals.branch_id
    AND branch_users.user_id = auth.uid()
  )
);

-- Dues
CREATE TABLE dues (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  user_id UUID REFERENCES users(id),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  party TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('receivable', 'payable')),
  status TEXT DEFAULT 'not_received' CHECK (status IN ('received', 'not_received')),
  remarks TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Cash closings
CREATE TABLE cash_closings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  user_id UUID REFERENCES users(id),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  opening NUMERIC(12,2) NOT NULL,
  total_cash_sales NUMERIC(12,2) NOT NULL,
  total_expenses NUMERIC(12,2) NOT NULL,
  counted_cash NUMERIC(12,2) NOT NULL,
  withdrawn NUMERIC(12,2) NOT NULL,
  withdrawn_notes TEXT,
  adjustments NUMERIC(12,2),
  next_opening NUMERIC(12,2) NOT NULL,
  discrepancy NUMERIC(12,2),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT cash_closings_date_branch_unique UNIQUE (date, branch_id)
);

-- Safe balances (current balance per branch)
CREATE TABLE safe_balances (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE UNIQUE,
  balance NUMERIC(12,2) NOT NULL DEFAULT 0,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Safe transactions (all deposits and withdrawals)
CREATE TABLE safe_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  user_id UUID REFERENCES users(id),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('deposit', 'withdrawal')),
  amount NUMERIC(12,2) NOT NULL,
  note TEXT,
  cash_closing_id UUID REFERENCES cash_closings(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Fixed expenses (branch-specific recurring expenses like rent, electricity, etc.)
CREATE TABLE fixed_expenses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  user_id UUID REFERENCES users(id),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  category TEXT NOT NULL DEFAULT 'other',
  amount NUMERIC(12,2) NOT NULL,
  note TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security on safe_balances
ALTER TABLE safe_balances ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can read safe_balances for branches they have access to
CREATE POLICY "Users can read safe_balances for their branches"
ON safe_balances
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = safe_balances.branch_id
    AND branch_users.user_id = auth.uid()
  )
);

-- RLS Policy: Users can update safe_balances for branches they have access to
CREATE POLICY "Users can update safe_balances for their branches"
ON safe_balances
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = safe_balances.branch_id
    AND branch_users.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = safe_balances.branch_id
    AND branch_users.user_id = auth.uid()
  )
);

-- RLS Policy: Users can insert safe_balances for branches they have access to
CREATE POLICY "Users can insert safe_balances for their branches"
ON safe_balances
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = safe_balances.branch_id
    AND branch_users.user_id = auth.uid()
  )
);

-- Enable Row Level Security on safe_transactions
ALTER TABLE safe_transactions ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can read safe_transactions for branches they have access to
CREATE POLICY "Users can read safe_transactions for their branches"
ON safe_transactions
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = safe_transactions.branch_id
    AND branch_users.user_id = auth.uid()
  )
);

-- RLS Policy: Users can insert safe_transactions for branches they have access to
CREATE POLICY "Users can insert safe_transactions for their branches"
ON safe_transactions
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = safe_transactions.branch_id
    AND branch_users.user_id = auth.uid()
  )
);

-- RLS Policy: Only owners/managers can delete safe_transactions
CREATE POLICY "Owners can delete safe_transactions"
ON safe_transactions
FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = safe_transactions.branch_id
    AND branch_users.user_id = auth.uid()
    AND branch_users.role IN ('business_owner', 'owner', 'manager')
  )
);

-- Enable Row Level Security on fixed_expenses
ALTER TABLE fixed_expenses ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can read fixed_expenses for branches they have access to
CREATE POLICY "Users can read fixed_expenses for their branches"
ON fixed_expenses
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = fixed_expenses.branch_id
    AND branch_users.user_id = auth.uid()
  )
);

-- RLS Policy: Users can insert fixed_expenses for branches they have access to
CREATE POLICY "Users can insert fixed_expenses for their branches"
ON fixed_expenses
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = fixed_expenses.branch_id
    AND branch_users.user_id = auth.uid()
  )
);

-- RLS Policy: Users can update fixed_expenses for branches they have access to
CREATE POLICY "Users can update fixed_expenses for their branches"
ON fixed_expenses
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = fixed_expenses.branch_id
    AND branch_users.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = fixed_expenses.branch_id
    AND branch_users.user_id = auth.uid()
  )
);

-- RLS Policy: Only owners/managers can delete fixed_expenses
CREATE POLICY "Owners can delete fixed_expenses"
ON fixed_expenses
FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.branch_id = fixed_expenses.branch_id
    AND branch_users.user_id = auth.uid()
    AND branch_users.role IN ('business_owner', 'owner', 'manager')
  )
);

-- Function to update safe balance when a transaction is created
CREATE OR REPLACE FUNCTION update_safe_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Insert or update safe balance
    INSERT INTO safe_balances (branch_id, balance, updated_at)
    VALUES (
      NEW.branch_id,
      CASE 
        WHEN NEW.type = 'deposit' THEN NEW.amount
        ELSE -NEW.amount
      END,
      NOW()
    )
    ON CONFLICT (branch_id) DO UPDATE
    SET balance = safe_balances.balance + 
        CASE 
          WHEN NEW.type = 'deposit' THEN NEW.amount
          ELSE -NEW.amount
        END,
        updated_at = NOW();
  ELSIF TG_OP = 'DELETE' THEN
    -- Reverse the transaction effect
    UPDATE safe_balances
    SET balance = balance - 
        CASE 
          WHEN OLD.type = 'deposit' THEN OLD.amount
          ELSE -OLD.amount
        END,
        updated_at = NOW()
    WHERE branch_id = OLD.branch_id;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Trigger to automatically update safe balance
CREATE TRIGGER safe_balance_update_trigger
AFTER INSERT OR DELETE ON safe_transactions
FOR EACH ROW
EXECUTE FUNCTION update_safe_balance();

-- Create indexes for performance
CREATE INDEX idx_cash_expenses_date ON cash_expenses(date);
CREATE INDEX idx_cash_expenses_branch ON cash_expenses(branch_id);
CREATE INDEX idx_online_expenses_date ON online_expenses(date);
CREATE INDEX idx_online_expenses_branch ON online_expenses(branch_id);
CREATE INDEX idx_credit_expenses_date ON credit_expenses(date);
CREATE INDEX idx_credit_expenses_branch ON credit_expenses(branch_id);
CREATE INDEX idx_cash_counts_date ON cash_counts(date);
CREATE INDEX idx_cash_counts_branch ON cash_counts(branch_id);
CREATE INDEX idx_card_sales_date ON card_sales(date);
CREATE INDEX idx_card_sales_branch ON card_sales(branch_id);
CREATE INDEX idx_card_machines_branch ON card_machines(branch_id);
CREATE INDEX idx_online_sales_date ON online_sales(date);
CREATE INDEX idx_online_sales_branch ON online_sales(branch_id);
CREATE INDEX idx_qr_payments_date ON qr_payments(date);
CREATE INDEX idx_qr_payments_branch ON qr_payments(branch_id);
CREATE INDEX idx_dues_date ON dues(date);
CREATE INDEX idx_dues_branch ON dues(branch_id);
CREATE INDEX idx_cash_closings_date ON cash_closings(date);
CREATE INDEX idx_cash_closings_branch ON cash_closings(branch_id);
CREATE INDEX idx_safe_balances_branch ON safe_balances(branch_id);
CREATE INDEX idx_safe_transactions_date ON safe_transactions(date);
CREATE INDEX idx_safe_transactions_branch ON safe_transactions(branch_id);
CREATE INDEX idx_safe_transactions_type ON safe_transactions(type);
CREATE INDEX idx_fixed_expenses_branch_date ON fixed_expenses(branch_id, date DESC);
CREATE INDEX idx_fixed_expenses_date ON fixed_expenses(date DESC);
CREATE INDEX idx_suppliers_business ON suppliers(business_id);
CREATE INDEX idx_branch_users_business ON branch_users(business_id);
CREATE INDEX idx_pending_users_email ON pending_users(email);
CREATE INDEX idx_pending_users_business_id ON pending_users(business_id);

-- Ensure each branch keeps at least one business owner
CREATE OR REPLACE FUNCTION check_at_least_one_owner()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  owner_count INTEGER;
  branch_uuid UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    branch_uuid := OLD.branch_id;
  ELSE
    branch_uuid := NEW.branch_id;
  END IF;

  IF TG_OP = 'DELETE' AND OLD.role = 'business_owner' THEN
    SELECT COUNT(*) INTO owner_count
    FROM branch_users
    WHERE branch_id = branch_uuid
      AND role = 'business_owner'
      AND id != OLD.id;

    IF owner_count = 0 THEN
      RAISE EXCEPTION 'Cannot delete the last business owner. A branch must have at least one business owner.';
    END IF;
  ELSIF TG_OP = 'UPDATE'
        AND OLD.role = 'business_owner'
        AND NEW.role != 'business_owner' THEN
    SELECT COUNT(*) INTO owner_count
    FROM branch_users
    WHERE branch_id = branch_uuid
      AND role = 'business_owner'
      AND id != NEW.id;

    IF owner_count = 0 THEN
      RAISE EXCEPTION 'Cannot change role. A branch must have at least one business owner.';
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER enforce_at_least_one_owner
BEFORE DELETE OR UPDATE ON branch_users
FOR EACH ROW
EXECUTE FUNCTION check_at_least_one_owner();

-- Helper function: check if a user is a business owner for a business
CREATE OR REPLACE FUNCTION check_business_owner(business_uuid uuid, user_uuid uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM branch_users
    WHERE business_id = business_uuid
      AND user_id = user_uuid
      AND role = 'business_owner'
  );
END;
$$;

-- Helper to insert/update user rows when adding via owner UI
CREATE OR REPLACE FUNCTION insert_user_for_owner(
  p_user_id uuid,
  p_name text,
  p_email text,
  p_phone text DEFAULT NULL::text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_owner_id UUID;
BEGIN
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM branch_users
    WHERE user_id = v_owner_id
      AND role IN ('business_owner', 'owner')
  ) THEN
    RAISE EXCEPTION 'Only business owners and owners can create users. Current user: %', v_owner_id;
  END IF;

  INSERT INTO users (id, name, email, phone)
  VALUES (p_user_id, p_name, p_email, p_phone)
  ON CONFLICT (id) DO UPDATE
  SET name = EXCLUDED.name,
      email = EXCLUDED.email,
      phone = EXCLUDED.phone;
END;
$$;

CREATE OR REPLACE FUNCTION insert_user_for_owner_by_email(
  p_email text,
  p_name text,
  p_phone text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_owner_id UUID;
  v_user_id UUID;
BEGIN
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM branch_users
    WHERE user_id = v_owner_id
      AND role IN ('business_owner', 'owner')
  ) THEN
    RAISE EXCEPTION 'Only business owners and owners can create users. Current user: %', v_owner_id;
  END IF;

  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = p_email
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'User with email % does not exist in authentication system. Please create the user account first.', p_email;
  END IF;

  INSERT INTO users (id, name, email, phone)
  VALUES (v_user_id, p_name, p_email, p_phone)
  ON CONFLICT (id) DO UPDATE
  SET name = EXCLUDED.name,
      email = EXCLUDED.email,
      phone = EXCLUDED.phone;

  RETURN v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION is_business_owner(user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM branch_users
    WHERE branch_users.user_id = is_business_owner.user_id
      AND role = 'business_owner'
  );
END;
$$;

CREATE OR REPLACE FUNCTION is_business_owner_for_policy(p_business_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM branch_users
    WHERE business_id = p_business_id
      AND user_id = p_user_id
      AND role = 'business_owner'
  );
END;
$$;

CREATE OR REPLACE FUNCTION is_user_owner(user_uuid uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM branch_users
    WHERE user_id = user_uuid
      AND role IN ('owner', 'business_owner')
  );
END;
$$;

CREATE OR REPLACE FUNCTION make_user_business_owner(p_user_id uuid, p_business_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_user_id UUID;
  v_branch_id UUID;
BEGIN
  v_current_user_id := auth.uid();
  IF v_current_user_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM branch_users
    WHERE business_id = p_business_id
      AND user_id = v_current_user_id
      AND role = 'business_owner'
  ) THEN
    RAISE EXCEPTION 'Only business owners can make other users business owners';
  END IF;

  FOR v_branch_id IN SELECT id FROM branches WHERE business_id = p_business_id LOOP
    INSERT INTO branch_users (branch_id, user_id, business_id, role)
    VALUES (v_branch_id, p_user_id, p_business_id, 'business_owner')
    ON CONFLICT (branch_id, user_id) DO UPDATE
    SET role = 'business_owner',
        business_id = EXCLUDED.business_id;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION user_owns_all_branches(business_uuid uuid, user_uuid uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
AS $$
DECLARE
  branch_count INTEGER;
  owner_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO branch_count
  FROM branches
  WHERE business_id = business_uuid;
  
  IF branch_count = 0 THEN
    RETURN TRUE;
  END IF;
  
  SELECT COUNT(*) INTO owner_count
  FROM branches b
  INNER JOIN branch_users bu ON b.id = bu.branch_id
  WHERE b.business_id = business_uuid
    AND bu.user_id = user_uuid
    AND bu.role IN ('owner', 'business_owner');
  
  RETURN owner_count = branch_count AND branch_count > 0;
END;
$$;

-- Automatically assign all business owners (including read-only) to a new branch when it's created
CREATE OR REPLACE FUNCTION auto_assign_business_owners_to_branch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  owner_record RECORD;
BEGIN
  -- Get all distinct business owners (including read-only) for this business
  FOR owner_record IN
    SELECT DISTINCT user_id, role
    FROM branch_users
    WHERE business_id = NEW.business_id
      AND role IN ('business_owner', 'business_owner_read_only')
  LOOP
    -- Insert branch_user record for each business owner (preserve their role)
    INSERT INTO branch_users (branch_id, user_id, business_id, role)
    VALUES (NEW.id, owner_record.user_id, NEW.business_id, owner_record.role)
    ON CONFLICT (branch_id, user_id) DO NOTHING;
  END LOOP;
  
  RETURN NEW;
END;
$$;

CREATE TRIGGER auto_assign_owners_on_branch_insert
AFTER INSERT ON branches
FOR EACH ROW
EXECUTE FUNCTION auto_assign_business_owners_to_branch();

