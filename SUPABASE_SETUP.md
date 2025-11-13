# Supabase Setup Guide

## Step 1: Create Supabase Project

1. Go to [https://supabase.com](https://supabase.com)
2. Sign up or log in
3. Click "New Project"
4. Fill in:
   - **Name**: business_finance_manager (or your choice)
   - **Database Password**: Create a strong password (save it!)
   - **Region**: Choose closest to you
   - Click "Create new project"

## Step 2: Get API Credentials

1. In your Supabase project dashboard, go to **Settings** → **API**
2. Copy:
   - **Project URL** (e.g., `https://xxxxxxxxxxxxx.supabase.co`)
   - **anon/public key** (the long JWT token)

## Step 3: Update Flutter Config

1. Open `lib/config/supabase_config.dart`
2. Replace `YOUR_SUPABASE_URL` with your Project URL
3. Replace `YOUR_SUPABASE_ANON_KEY` with your anon key

## Step 4: Create Database Tables

Run these SQL commands in Supabase SQL Editor (Settings → SQL Editor):

```sql
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
  owner_id UUID REFERENCES users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Branches table
CREATE TABLE branches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  business_id UUID REFERENCES businesses(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  location TEXT NOT NULL,
  manager_id UUID REFERENCES users(id),
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Branch users (junction table for user-branch-role)
CREATE TABLE branch_users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('owner', 'manager', 'staff')),
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
CREATE INDEX idx_cash_counts_date ON cash_counts(date);
CREATE INDEX idx_cash_counts_branch ON cash_counts(branch_id);
CREATE INDEX idx_card_sales_date ON card_sales(date);
CREATE INDEX idx_card_sales_branch ON card_sales(branch_id);
CREATE INDEX idx_online_sales_date ON online_sales(date);
CREATE INDEX idx_online_sales_branch ON online_sales(branch_id);
CREATE INDEX idx_qr_payments_date ON qr_payments(date);
CREATE INDEX idx_qr_payments_branch ON qr_payments(branch_id);
CREATE INDEX idx_dues_date ON dues(date);
CREATE INDEX idx_dues_branch ON dues(branch_id);
CREATE INDEX idx_cash_closings_date ON cash_closings(date);
CREATE INDEX idx_cash_closings_branch ON cash_closings(branch_id);
```

## Step 5: Enable Row Level Security (RLS)

Run this in SQL Editor to enable RLS and create policies:

```sql
-- Enable RLS on all tables
ALTER TABLE cash_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE card_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE online_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE qr_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE dues ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_closings ENABLE ROW LEVEL SECURITY;
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE branch_users ENABLE ROW LEVEL SECURITY;

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

-- Policy: Users can view their assigned branches
CREATE POLICY branch_access ON branches
  FOR SELECT
  USING (
    id IN (
      SELECT branch_id FROM branch_users 
      WHERE user_id = auth.uid()
    )
  );

-- Policy: Users can view their branch assignments
CREATE POLICY branch_user_view ON branch_users
  FOR SELECT
  USING (user_id = auth.uid());
```

## Step 6: Enable Phone Authentication

1. Go to **Authentication** → **Providers** in Supabase dashboard
2. Enable **Phone** provider
3. Configure SMS settings (you may need to add credits)

## Step 7: Update Flutter Code

1. Initialize Supabase in `main.dart` (see next section)
2. Update `AuthService` to use Supabase auth
3. Update `DatabaseService` to use Supabase client

## Next Steps

After setup, update the Flutter app to use Supabase instead of mock data.

