-- Remove the final warning reported for place_order while retaining the seller
-- existence check and its use of PL/pgSQL's FOUND status.
do $$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef('public.place_order(jsonb)'::regprocedure)
  into function_sql;

  updated_sql := replace(
    function_sql,
    'seller_profile public.profiles%rowtype;',
    ''
  );
  updated_sql := replace(
    updated_sql,
    'select * into seller_profile from public.profiles',
    'perform 1 from public.profiles'
  );

  if updated_sql = function_sql
     or position('seller_profile public.profiles%rowtype;' in updated_sql) > 0
     or position('into seller_profile' in updated_sql) > 0 then
    raise exception 'Could not safely remove the unused place_order variable.';
  end if;

  execute updated_sql;
end;
$$;
