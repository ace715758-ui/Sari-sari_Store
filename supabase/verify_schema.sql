-- Run this to see exactly what columns products and sales tables have
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('products', 'sales', 'daily_closings')
order by table_name, ordinal_position;
