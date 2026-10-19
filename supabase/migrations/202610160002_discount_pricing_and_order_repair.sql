-- Keep order totals authoritative on the server and charge the same discounted
-- price displayed by the Flutter client. This repair also resolves PL/pgSQL
-- ambiguities reported by `supabase db lint`.
do $$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef('public.place_order(jsonb)'::regprocedure)
  into function_sql;

  updated_sql := replace(function_sql,
    'seller_list bigint[] := ''{}'';',
    'seller_list bigint[] := array[]::bigint[];');
  updated_sql := replace(updated_sql,
    'product_list bigint[] := ''{}'';',
    'product_list bigint[] := array[]::bigint[];');
  updated_sql := replace(updated_sql,
    'item_price := (option_row ->> ''price'')::numeric;',
    'item_price := round((option_row ->> ''price'')::numeric * (100 - product_row.discount_percent)::numeric / 100, 2);');
  updated_sql := replace(updated_sql,
    'item_price := product_row.price;',
    'item_price := round(product_row.price * (100 - product_row.discount_percent)::numeric / 100, 2);');
  updated_sql := replace(updated_sql,
    'sum(quantity * item_price)',
    'sum(public.order_items.quantity * public.order_items.item_price)');

  if updated_sql = function_sql
     or position('item_price := product_row.price;' in updated_sql) > 0
     or position('item_price := (option_row ->> ''price'')::numeric;' in updated_sql) > 0 then
    raise exception 'Could not safely patch public.place_order(jsonb).';
  end if;

  execute updated_sql;
end;
$$;
