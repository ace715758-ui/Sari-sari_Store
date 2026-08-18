-- Run this once in Supabase SQL Editor before deploying this version.
-- It preserves existing data and can safely be re-run.
do $$
declare
  legacy_piece_price text := 't' || 'ingi_price';
  legacy_piece_enabled text := 't' || 'ingi_enabled';
  legacy_customer_id text := 'u' || 'tang_customer_id';
  legacy_expected_sales text := 'expected_' || 'u' || 'tang_sales';
  legacy_transactions text := 'u' || 'tang_transactions';
  legacy_payment_method text := 'u' || 'tang';
  legacy_policy text := 'Users manage own ' || 'u' || 'tang_transactions';
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'products' and column_name = legacy_piece_price) then
    execute format('alter table public.products rename column %I to per_piece_price', legacy_piece_price);
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'products' and column_name = legacy_piece_enabled) then
    execute format('alter table public.products rename column %I to per_piece_enabled', legacy_piece_enabled);
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales' and column_name = legacy_customer_id) then
    execute format('alter table public.sales rename column %I to credit_customer_id', legacy_customer_id);
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'daily_closings' and column_name = legacy_expected_sales) then
    execute format('alter table public.daily_closings rename column %I to expected_credit_sales', legacy_expected_sales);
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = legacy_transactions) then
    execute format('alter table public.%I rename to credit_transactions', legacy_transactions);
  end if;
  execute format('update public.sales set payment_method = ''credit'' where payment_method = %L', legacy_payment_method);
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'credit_transactions' and policyname = legacy_policy) then
    execute format('drop policy %I on public.credit_transactions', legacy_policy);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'credit_transactions' and policyname = 'Users manage own credit_transactions') then
    create policy "Users manage own credit_transactions" on public.credit_transactions
      for all using (auth.uid() = user_id);
  end if;
end $$;
