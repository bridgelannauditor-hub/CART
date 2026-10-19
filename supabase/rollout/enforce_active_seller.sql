-- STAGED ENFORCEMENT: not a migration. Do not move this file into
-- supabase/migrations until the rollout gates in the README are complete:
-- legacy Sellers reviewed, approved Sellers given seller_accounts rows,
-- outstanding orders covered by fulfillment grants, and clients updated.
--
-- Once applied, an account can do the following only with an active
-- seller_accounts row (created by public.admin_review_seller_application):
--
--   Feature                                   Before approval
--   Publish products for sale                 Not allowed
--   Accept and fulfil orders as a seller      Not allowed (except exact-order grants)
--   Start live selling                        Not allowed
--   Create shop promotions                    Not allowed
--   Browse/buy, apply, verify, draft a shop   Allowed (unchanged)

begin;

-- 1. Every RLS policy and RPC that calls private.is_seller() (product
--    update/delete, follower campaigns, live sessions) now requires approval
--    instead of trusting profiles.account_type.
create or replace function private.is_seller()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_active_seller_authorization(private.current_profile_id());
$$;

-- 2. Product creation. create_product still checks account_type; this trigger
--    adds the approval check for every end-user insert path. The `role`
--    setting is what PostgREST sets for API requests and it survives SECURITY
--    DEFINER calls such as create_product, while trusted service-role and
--    operator maintenance is not affected.
create or replace function private.enforce_active_seller_product()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('role', true) in ('authenticated', 'anon')
     and not private.has_active_seller_authorization(new.seller_id) then
    raise exception 'Seller approval is required before publishing products.' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_active_seller_product on public.products;
create trigger enforce_active_seller_product
before insert on public.products
for each row execute function private.enforce_active_seller_product();

-- 3. Seller-side order changes need approval or an exact-order fulfillment
--    grant. Buyer-side changes (for example a buyer cancelling) are unaffected.
create or replace function private.enforce_active_seller_fulfillment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('role', true) in ('authenticated', 'anon')
     and new.seller_id = private.current_profile_id()
     and not private.can_fulfill_seller_order(new.seller_id, new.order_id) then
    raise exception 'Seller approval is required to fulfil this order.' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_active_seller_fulfillment on public.order_items;
create trigger enforce_active_seller_fulfillment
before update on public.order_items
for each row execute function private.enforce_active_seller_fulfillment();

revoke all on function private.enforce_active_seller_product() from public, anon, authenticated;
revoke all on function private.enforce_active_seller_fulfillment() from public, anon, authenticated;

commit;
