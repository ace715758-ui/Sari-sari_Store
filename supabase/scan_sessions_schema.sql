-- Run in Supabase SQL Editor

-- Barcode products lookup table (shared, no price fields)
create table if not exists public.barcode_products (
  barcode          text primary key,
  name             text not null,
  category         text not null default '',
  pieces_per_pack  integer not null default 1,
  selling_mode     text not null default 'pack' check (selling_mode in ('pack', 'per-piece')),
  created_at       timestamptz not null default now()
);

-- Scan sessions table
create table if not exists public.scan_sessions (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  status           text not null default 'waiting' check (status in ('waiting', 'scanned', 'expired')),
  scanned_barcode  text,
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null default (now() + interval '10 minutes')
);

-- RLS
alter table public.barcode_products enable row level security;
alter table public.scan_sessions enable row level security;

-- barcode_products: readable by anyone (public lookup), writable only by authenticated users
drop policy if exists "Anyone can read barcode_products" on public.barcode_products;
create policy "Anyone can read barcode_products" on public.barcode_products
  for select using (true);

drop policy if exists "Authenticated users can insert barcode_products" on public.barcode_products;
create policy "Authenticated users can insert barcode_products" on public.barcode_products
  for insert with check (auth.uid() is not null);

-- scan_sessions: owner can do anything; phone (anon) can update status/barcode only if session matches
drop policy if exists "Owner manages own scan sessions" on public.scan_sessions;
create policy "Owner manages own scan sessions" on public.scan_sessions
  for all using (auth.uid() = user_id);

-- Allow phone (unauthenticated) to read a session by id (needed to validate before scan)
drop policy if exists "Anyone can read scan sessions" on public.scan_sessions;
create policy "Anyone can read scan sessions" on public.scan_sessions
  for select using (true);

-- Allow phone (unauthenticated) to update status+barcode on a waiting, non-expired session
drop policy if exists "Anyone can submit a scan" on public.scan_sessions;
create policy "Anyone can submit a scan" on public.scan_sessions
  for update using (
    status = 'waiting'
    and expires_at > now()
  )
  with check (
    status = 'scanned'
  );

-- Enable Realtime on scan_sessions
alter publication supabase_realtime add table public.scan_sessions;

-- Index for cleanup queries
create index if not exists scan_sessions_expires_idx on public.scan_sessions(expires_at);
