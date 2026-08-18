-- Run this in your Supabase SQL Editor

create table if not exists public.daily_closings (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references auth.users(id) on delete cascade,
  date                  date not null,
  opening_cash          numeric(12,2) not null default 0,
  expected_cash_sales   numeric(12,2) not null default 0,
  expected_credit_sales numeric(12,2) not null default 0,
  cash_payouts          jsonb not null default '[]'::jsonb,  -- [{amount, note}]
  actual_cash_counted   numeric(12,2),
  variance              numeric(12,2),
  status                text not null default 'open' check (status in ('open','closed')),
  notes                 text not null default '',
  closed_at             timestamptz,
  created_at            timestamptz not null default now(),
  unique (user_id, date)
);

alter table public.daily_closings enable row level security;

create policy "Users manage own closings" on public.daily_closings
  for all using (auth.uid() = user_id);

create index if not exists daily_closings_user_date_idx
  on public.daily_closings(user_id, date desc);
