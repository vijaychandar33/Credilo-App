-- Migration: Add online_expenses table
-- Run this in Supabase SQL Editor to add support for Online Daily Expenses

-- Online expenses (for UPI/bank transfer payments)
CREATE TABLE IF NOT EXISTS online_expenses (
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

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_online_expenses_date ON online_expenses(date);
CREATE INDEX IF NOT EXISTS idx_online_expenses_branch ON online_expenses(branch_id);

