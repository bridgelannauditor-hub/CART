-- Two fixes found in the tester-reported bug audit.
--
-- 1. A customer who also has a shop could not order: place_order required a
--    'Customer' account, and approved sellers have account_type 'Seller'. A
--    seller may now buy like any customer, but never their own products.
--    The function is rewritten from its live definition so the flash sale,
--    voucher and stock logic stays exactly as deployed.
--
-- 2. "Unsend" a message silently did nothing: messages and conversations had
--    no DELETE policy, so row-level security matched zero rows.

do $$
declare
  definition text;
  patched text;
  customer_check constant text :=
    'where auth_user_id = auth.uid() and account_type = ''Customer'';';
  product_check constant text :=
    'if not found then raise exception ''A selected product is unavailable.'' using errcode = ''P0002''; end if;';
begin
  definition := pg_get_functiondef('public.place_order(jsonb)'::regprocedure);
  if position(customer_check in definition) = 0
     or position(product_check in definition) = 0 then
    raise exception 'place_order has an unexpected definition; not changing it.';
  end if;

  patched := replace(
    definition,
    customer_check,
    'where auth_user_id = auth.uid() and account_type in (''Customer'', ''Seller'');'
  );
  patched := replace(
    patched,
    product_check,
    product_check || E'\n'
      || '    if product_row.seller_id = customer_profile.id then'
      || ' raise exception ''You cannot order your own product.'''
      || ' using errcode = ''23514''; end if;'
  );
  execute patched;
end;
$$;

create policy messages_sender_delete on public.messages
  for delete to authenticated
  using (sender_id = (select private.current_profile_id()));

-- A conversation can only be removed once it has no messages left.
create policy conversations_participant_delete on public.conversations
  for delete to authenticated
  using (
    (select private.current_profile_id()) = any (participant_ids)
    and not exists (
      select 1 from public.messages m where m.conversation_id = conversations.id
    )
  );
