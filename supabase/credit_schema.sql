-- Run this in your Supabase SQL Editor

-- Customers table
create table if not exists customers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  contact_number text not null default '',
  notes text not null default '',
  current_balance numeric not null default 0,
  created_at timestamptz not null default now()
);

-- Credit transactions table
create table if not exists credit_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  type text not null check (type in ('charge', 'payment')),
  amount numeric not null check (amount > 0),
  related_sale_id uuid references sales(id) on delete set null,
  note text not null default '',
  created_at timestamptz not null default now()
);

-- Add credit_customer_id to sales so we know which sale was on credit
alter table sales add column if not exists payment_method text not null default 'cash';
alter table sales add column if not exists credit_customer_id uuid references customers(id) on delete set null;

-- RLS
alter table customers enable row level security;
alter table credit_transactions enable row level security;

create policy "Users manage own customers" on customers
  for all using (auth.uid() = user_id);

create policy "Users manage own credit_transactions" on credit_transactions
  for all using (auth.uid() = user_id);
