-- Run this in your Supabase SQL Editor after the existing schema files.

alter table public.products
  add column if not exists low_stock_threshold integer check (low_stock_threshold is null or low_stock_threshold >= 0),
  add column if not exists has_expiry boolean not null default false,
  add column if not exists expiry_tracking_mode text not null default 'product-level' check (expiry_tracking_mode in ('product-level', 'batch')),
  add column if not exists expiry_date date;

alter table public.store_settings
  add column if not exists expiry_warning_days integer not null default 7 check (expiry_warning_days >= 0),
  add column if not exists per_product_thresholds_enabled boolean not null default true;

create table if not exists public.expiry_batches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity integer not null check (quantity >= 0),
  expiry_date date not null,
  date_added timestamptz not null default now(),
  notes text not null default ''
);

alter table public.expiry_batches enable row level security;

drop policy if exists "Users can manage their own expiry batches" on public.expiry_batches;
create policy "Users can manage their own expiry batches"
on public.expiry_batches
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create index if not exists expiry_batches_user_product_idx on public.expiry_batches(user_id, product_id);
create index if not exists expiry_batches_user_expiry_idx on public.expiry_batches(user_id, expiry_date);
