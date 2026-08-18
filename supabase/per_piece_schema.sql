-- Run this in your Supabase SQL Editor after credit_schema.sql

-- Add per-piece fields to products table
alter table public.products
  add column if not exists pieces_per_pack  integer not null default 1 check (pieces_per_pack >= 1),
  add column if not exists per_piece_price   numeric(12,2) not null default 0 check (per_piece_price >= 0),
  add column if not exists per_piece_enabled boolean not null default false;

-- Add sell_mode to sales table so we know if a sale was by piece or by pack
alter table public.sales
  add column if not exists sell_mode text not null default 'pack' check (sell_mode in ('pack', 'piece'));

-- Existing products: piecesPerPack=1, isPerPieceEnabled=false — they behave exactly as before
-- No data migration needed; defaults handle backwards compatibility
