-- credilo - Database Schema
-- Copy and paste this entire file into Supabase SQL Editor

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

-- Branch users (junction table for user-branch-role)
CREATE TABLE branch_users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('business_owner', 'owner', 'manager', 'staff')),
  permissions JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(branch_id, user_id)
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
  txn_count INTEGER,
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
  settlement_date DATE,
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
  amount NUMERIC(12,2) NOT NULL,
  txn_id TEXT,
  settlement_date DATE,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Dues
CREATE TABLE dues (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL,
  user_id UUID REFERENCES users(id),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  party TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  due_date DATE NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('receivable', 'payable')),
  status TEXT NOT NULL CHECK (status IN ('open', 'partially_paid', 'paid')),
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
  adjustments NUMERIC(12,2),
  next_opening NUMERIC(12,2) NOT NULL,
  discrepancy NUMERIC(12,2),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX idx_cash_expenses_date ON cash_expenses(date);
CREATE INDEX idx_cash_expenses_branch ON cash_expenses(branch_id);
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
CREATE INDEX idx_suppliers_business ON suppliers(business_id);
CREATE INDEX idx_branch_users_business ON branch_users(business_id);

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

-- Automatically assign all business owners to a new branch when it's created
CREATE OR REPLACE FUNCTION auto_assign_business_owners_to_branch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  owner_record RECORD;
BEGIN
  -- Get all distinct business owners for this business
  FOR owner_record IN
    SELECT DISTINCT user_id
    FROM branch_users
    WHERE business_id = NEW.business_id
      AND role = 'business_owner'
  LOOP
    -- Insert branch_user record for each business owner
    INSERT INTO branch_users (branch_id, user_id, business_id, role)
    VALUES (NEW.id, owner_record.user_id, NEW.business_id, 'business_owner')
    ON CONFLICT (branch_id, user_id) DO NOTHING;
  END LOOP;
  
  RETURN NEW;
END;
$$;

CREATE TRIGGER auto_assign_owners_on_branch_insert
AFTER INSERT ON branches
FOR EACH ROW
EXECUTE FUNCTION auto_assign_business_owners_to_branch();

