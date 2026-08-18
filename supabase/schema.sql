create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  category text not null,
  price numeric(12, 2) not null check (price > 0),
  cost_price numeric(12, 2) not null check (cost_price >= 0),
  quantity integer not null check (quantity >= 0),
  pieces_per_pack integer not null default 1 check (pieces_per_pack >= 1),
  per_piece_price numeric(12, 2) not null default 0 check (per_piece_price >= 0),
  per_piece_enabled boolean not null default false,
  low_stock_threshold integer check (low_stock_threshold is null or low_stock_threshold >= 0),
  has_expiry boolean not null default false,
  expiry_tracking_mode text not null default 'product-level' check (expiry_tracking_mode in ('product-level', 'batch')),
  expiry_date date,
  created_at timestamptz not null default now()
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  qty integer not null check (qty > 0),
  total numeric(12, 2) not null check (total >= 0),
  cost numeric(12, 2) not null check (cost >= 0),
  sold_at timestamptz not null default now()
);

create table if not exists public.expiry_batches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity integer not null check (quantity >= 0),
  expiry_date date not null,
  date_added timestamptz not null default now(),
  notes text not null default ''
);

create table if not exists public.store_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  store_name text not null default 'SariSari Store',
  owner_name text not null default 'Store Owner',
  currency text not null default '₱',
  low_stock_threshold integer not null default 5 check (low_stock_threshold >= 0),
  expiry_warning_days integer not null default 7 check (expiry_warning_days >= 0),
  per_product_thresholds_enabled boolean not null default true,
  dark_mode boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.products enable row level security;
alter table public.sales enable row level security;
alter table public.expiry_batches enable row level security;
alter table public.store_settings enable row level security;

drop policy if exists "Users can manage their own products" on public.products;
create policy "Users can manage their own products"
on public.products
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can manage their own sales" on public.sales;
create policy "Users can manage their own sales"
on public.sales
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can manage their own expiry batches" on public.expiry_batches;
create policy "Users can manage their own expiry batches"
on public.expiry_batches
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can manage their own settings" on public.store_settings;
create policy "Users can manage their own settings"
on public.store_settings
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create index if not exists products_user_id_idx on public.products(user_id);
create index if not exists expiry_batches_user_product_idx on public.expiry_batches(user_id, product_id);
create index if not exists expiry_batches_user_expiry_idx on public.expiry_batches(user_id, expiry_date);
create index if not exists sales_user_id_sold_at_idx on public.sales(user_id, sold_at desc);
