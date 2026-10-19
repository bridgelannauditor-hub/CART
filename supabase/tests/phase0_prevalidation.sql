-- Phase 0 local-only authorization validation.
--
-- Run only against a disposable Supabase database after `supabase db reset`:
--   supabase test db supabase/tests/phase0_prevalidation.sql
--
-- The fixed UUIDs and e-mail addresses below are test fixtures. The transaction
-- is rolled back. This file intentionally contains assertions for security
-- boundaries that are not enforced yet; those assertions must fail until the
-- corresponding containment migrations are reviewed and applied.

begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

-- Final catalog shape -------------------------------------------------------

select extensions.ok(
  (select relrowsecurity from pg_class where oid = 'public.seller_accounts'::regclass),
  'seller_accounts has RLS enabled'
);
select extensions.ok(
  (select relrowsecurity from pg_class where oid = 'public.seller_order_fulfillment_grants'::regclass),
  'seller_order_fulfillment_grants has RLS enabled'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.seller_accounts', 'SELECT')
    and not has_table_privilege('authenticated', 'public.seller_accounts', 'INSERT')
    and not has_table_privilege('authenticated', 'public.seller_accounts', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.seller_accounts', 'DELETE')
    and not has_any_column_privilege('authenticated', 'public.seller_accounts', 'SELECT')
    and not has_any_column_privilege('authenticated', 'public.seller_accounts', 'INSERT')
    and not has_any_column_privilege('authenticated', 'public.seller_accounts', 'UPDATE'),
  'authenticated has no seller_accounts table privileges'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.seller_order_fulfillment_grants', 'SELECT')
    and not has_table_privilege('authenticated', 'public.seller_order_fulfillment_grants', 'INSERT')
    and not has_table_privilege('authenticated', 'public.seller_order_fulfillment_grants', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.seller_order_fulfillment_grants', 'DELETE')
    and not has_any_column_privilege('authenticated', 'public.seller_order_fulfillment_grants', 'SELECT')
    and not has_any_column_privilege('authenticated', 'public.seller_order_fulfillment_grants', 'INSERT')
    and not has_any_column_privilege('authenticated', 'public.seller_order_fulfillment_grants', 'UPDATE'),
  'authenticated has no fulfillment-grant table privileges'
);
select extensions.ok(
  not has_function_privilege('authenticated', 'private.has_active_seller_authorization(bigint)', 'EXECUTE'),
  'arbitrary-profile active-seller helper is not client executable'
);
select extensions.ok(
  has_function_privilege('authenticated', 'private.has_active_seller_authorization()', 'EXECUTE'),
  'caller-bound active-seller helper is client executable'
);
select extensions.ok(
  not has_function_privilege('authenticated', 'private.can_fulfill_seller_order(bigint,bigint)', 'EXECUTE'),
  'arbitrary-profile order helper is not client executable'
);
select extensions.ok(
  has_function_privilege('authenticated', 'private.can_fulfill_seller_order(bigint)', 'EXECUTE'),
  'caller-bound order helper is client executable'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.submit_seller_application(jsonb)', 'EXECUTE'),
  'authenticated callers may execute the application RPC'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.seller_verification_applications', 'INSERT')
    and not has_any_column_privilege(
      'authenticated', 'public.seller_verification_applications', 'INSERT'
    ),
  'authenticated callers cannot insert applications directly'
);

select extensions.is(
  (select count(*)::integer from pg_trigger
   where tgrelid = 'auth.users'::regclass and not tgisinternal
     and tgname in ('on_auth_user_created', 'on_auth_user_email_confirmed',
                    'on_auth_user_verified_email_sync')),
  3,
  'the three intended Auth/profile triggers exist'
);
select extensions.is(
  (select count(*)::integer from pg_trigger
   where tgrelid = 'auth.users'::regclass and not tgisinternal
     and tgname in ('zz_capture_extended_seller_application',
                    'zz_sync_confirmed_school_email')),
  0,
  'metadata-trusting secondary Auth triggers are absent'
);
select extensions.is(
  (select count(*)::integer from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'has_active_seller_authorization'),
  2,
  'only the intended active-seller helper overloads exist'
);
select extensions.is(
  (select count(*)::integer from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'can_fulfill_seller_order'),
  2,
  'only the intended order-helper overloads exist'
);
select extensions.is(
  (select count(*)::integer from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname in ('handle_new_auth_user', 'sync_verified_auth_email',
                       'has_active_seller_authorization', 'can_fulfill_seller_order')
     -- PostgreSQL 18 stores SET search_path = '' as search_path="".
     and (not p.prosecdef
          or coalesce(p.proconfig, '{}') not in (array['search_path='],
                                                  array['search_path=""']))),
  0,
  'Phase 0 SECURITY DEFINER helpers use an empty search_path'
);

-- Auth/profile fixtures -----------------------------------------------------

insert into public.profiles
  (first_name, last_name, email, account_type)
values
  ('Existing', 'Buyer', 'phase0-existing-buyer@example.test', 'Customer');

insert into public.profiles
  (first_name, last_name, email, account_type)
values
  ('Pending', 'Buyer', 'phase0-pending-buyer@example.test', 'Customer');

insert into public.profiles
  (first_name, last_name, email, account_type, shop_name)
values
  ('Legacy', 'Seller', 'phase0-legacy-seller@example.test', 'Seller', 'Legacy Test Shop');

insert into auth.users
  (id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('10000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'phase0-forged@example.test', '', now(), '{}',
   '{"account_type":"Seller","role":"Admin","reviewer":true,"moderator":true,"support":true,"is_verified_seller":true,"listingLimit":999999,"trustScore":100,"seller_verification":{"status":"approved","identityCaptureCompleted":true,"faceCaptureCompleted":true}}',
   now(), now()),
  ('10000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'phase0-existing-buyer@example.test', '', now(), '{}',
   '{"account_type":"Seller","role":"Admin"}', now(), now()),
  ('10000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'phase0-legacy-seller@example.test', '', now(), '{}',
   '{"account_type":"Seller"}', now(), now()),
  ('10000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'phase0-buyer2@example.test', '', now(), '{}', '{}', now(), now()),
  ('10000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated',
   'phase0-inactive-seller@example.test', '', now(), '{}', '{}', now(), now()),
  ('10000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated',
   'phase0-active-seller@example.test', '', now(), '{}', '{}', now(), now()),
  ('10000000-0000-0000-0000-000000000007', 'authenticated', 'authenticated',
   'phase0-other-seller@example.test', '', now(), '{}', '{}', now(), now());

insert into auth.users
  (id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('10000000-0000-0000-0000-000000000009', 'authenticated', 'authenticated',
   'phase0-linked-origin@example.test', '', now(), '{}', '{}', now(), now()),
  ('10000000-0000-0000-0000-000000000011', 'authenticated', 'authenticated',
   'phase0-pending-buyer@example.test', '', null, '{}',
   '{"account_type":"Seller","role":"Admin"}', now(), now());

select extensions.is(
  (select account_type from public.profiles
   where auth_user_id = '10000000-0000-0000-0000-000000000001'),
  'Customer',
  'forged signup metadata creates a Buyer profile'
);
select extensions.is(
  (select count(*)::integer from public.seller_accounts sa
   join public.profiles p on p.id = sa.profile_id
   where p.auth_user_id = '10000000-0000-0000-0000-000000000001'),
  0,
  'forged signup metadata creates no seller authorization'
);
select extensions.ok(
  (select not is_verified_seller and trust_score = 0 and seller_tier = 1
   from public.profiles
   where auth_user_id = '10000000-0000-0000-0000-000000000001'),
  'forged verification, trust, and tier metadata is ignored'
);
select extensions.is(
  (select auth_user_id from public.profiles
   where email = 'phase0-existing-buyer@example.test'),
  '10000000-0000-0000-0000-000000000002'::uuid,
  'a confirmed Auth identity links an existing unlinked Buyer profile'
);
select extensions.is(
  (select auth_user_id from public.profiles
   where email = 'phase0-legacy-seller@example.test'),
  null::uuid,
  'a public Auth event does not claim an unlinked legacy Seller profile'
);
select extensions.is(
  (select auth_user_id from public.profiles
   where email = 'phase0-pending-buyer@example.test'),
  null::uuid,
  'an unconfirmed Auth identity does not claim an existing Buyer profile'
);

update auth.users
set email_confirmed_at = now(), updated_at = now()
where id = '10000000-0000-0000-0000-000000000011';
select extensions.is(
  (select auth_user_id from public.profiles
   where email = 'phase0-pending-buyer@example.test'),
  '10000000-0000-0000-0000-000000000011'::uuid,
  'email confirmation links the intended existing Buyer profile'
);

update public.profiles
set email = 'phase0-linked-conflict@example.test'
where auth_user_id = '10000000-0000-0000-0000-000000000009';
select extensions.throws_ok(
  $$insert into auth.users
      (id, aud, role, email, encrypted_password, email_confirmed_at,
       raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values
      ('10000000-0000-0000-0000-000000000010', 'authenticated', 'authenticated',
       'phase0-linked-conflict@example.test', '', now(), '{}', '{}', now(), now())$$,
  '23505',
  'an Auth identity cannot take over a profile linked to another identity'
);

update auth.users
set email = 'phase0-buyer2-renamed@example.test', updated_at = now()
where id = '10000000-0000-0000-0000-000000000004';
select extensions.is(
  (select email from public.profiles
   where auth_user_id = '10000000-0000-0000-0000-000000000004'),
  'phase0-buyer2-renamed@example.test',
  'a confirmed Auth email change synchronizes only its linked profile'
);

select extensions.throws_ok(
  $$insert into auth.users
      (id, aud, role, email, encrypted_password, email_confirmed_at,
       raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values
      ('10000000-0000-0000-0000-000000000008', 'authenticated', 'authenticated',
       'phase0-forged@example.test', '', now(), '{}', '{}', now(), now())$$,
  '23505',
  'a duplicate Auth identity is rejected'
);

set local role service_role;
select extensions.lives_ok(
  $$update public.profiles
    set auth_user_id = '10000000-0000-0000-0000-000000000003'
    where email = 'phase0-legacy-seller@example.test' and auth_user_id is null$$,
  'a trusted service operation may recover an unlinked legacy Seller profile'
);
reset role;
select extensions.is(
  (select auth_user_id from public.profiles
   where email = 'phase0-legacy-seller@example.test'),
  '10000000-0000-0000-0000-000000000003'::uuid,
  'legacy Seller recovery links only the reviewed Auth identity'
);

-- Convert two ordinary fixture profiles into reviewed legacy Seller fixtures.
-- This is trusted setup, not an activation/backfill path.
update public.profiles
set account_type = 'Seller', shop_name = 'Inactive Test Shop'
where auth_user_id = '10000000-0000-0000-0000-000000000005';
update public.profiles
set account_type = 'Seller', shop_name = 'Active Test Shop'
where auth_user_id = '10000000-0000-0000-0000-000000000006';
update public.profiles
set account_type = 'Seller', shop_name = 'Other Test Shop'
where auth_user_id = '10000000-0000-0000-0000-000000000007';

insert into public.seller_accounts (profile_id, status, approved_by, approved_at, status_reason)
select id, 'active', '10000000-0000-0000-0000-000000000001', now(), 'Disposable validation fixture'
from public.profiles where auth_user_id = '10000000-0000-0000-0000-000000000006';

-- Seller application boundaries -------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select extensions.lives_ok(
  $$select public.submit_seller_application(
    '{"sellerType":"individual","firstName":"Test","lastName":"Applicant","birthDate":"1995-05-05","address":"Test address","identityDocumentType":"national_id","payoutMethod":"gcash","payoutAccountName":"Test Applicant","acceptedTermsVersion":"2026-10","status":"approved","listingLimit":999999,"schoolEmailVerified":true,"identityCaptureCompleted":true,"faceCaptureCompleted":true}'::jsonb
  )$$,
  'a Buyer may submit a valid seller application through the RPC'
);
select extensions.throws_ok(
  $$update public.seller_verification_applications
    set status = 'approved', listing_limit = 999999,
        school_email_verified = true, identity_capture_completed = true
    where profile_id = private.current_profile_id()$$,
  '42501',
  'an applicant cannot directly set review, limit, or verification fields'
);
select extensions.throws_ok(
  $$update public.profiles set account_type = 'Seller', is_verified_seller = true,
      trust_score = 100 where id = private.current_profile_id()$$,
  '42501',
  'an ordinary user cannot directly elevate profile trust or role fields'
);
select extensions.throws_ok(
  $$update public.profiles set email = 'attacker-controlled@example.test'
    where id = private.current_profile_id()$$,
  '42501',
  'an ordinary user cannot directly change the confirmed profile email'
);
select extensions.throws_ok(
  $$update public.seller_accounts set status = 'active'$$,
  '42501',
  'an ordinary user cannot update seller authorization rows'
);

reset role;
select extensions.is(
  (select status from public.seller_verification_applications a
   join public.profiles p on p.id = a.profile_id
   where p.auth_user_id = '10000000-0000-0000-0000-000000000001'),
  'under_review',
  'privileged application payload fields are ignored'
);
select extensions.ok(
  (select a.listing_limit = 5 and not a.school_email_verified
          and not a.identity_capture_completed and not a.face_capture_completed
   from public.seller_verification_applications a
   join public.profiles p on p.id = a.profile_id
   where p.auth_user_id = '10000000-0000-0000-0000-000000000001'),
  'server-owned application fields retain safe values'
);

update public.seller_verification_applications a
set status = 'rejected', reviewed_at = now()
from public.profiles p
where p.id = a.profile_id
  and p.auth_user_id = '10000000-0000-0000-0000-000000000001';

set local role authenticated;
select extensions.lives_ok(
  $$select public.submit_seller_application(
    '{"sellerType":"individual","firstName":"Test","lastName":"Applicant","birthDate":"1995-05-05","address":"Retry address","identityDocumentType":"passport","payoutMethod":"maya","payoutAccountName":"Test Applicant","acceptedTermsVersion":"2026-10"}'::jsonb
  )$$,
  'a rejected application may be retried'
);
reset role;

update public.seller_verification_applications a
set status = 'approved', reviewed_at = now()
from public.profiles p
where p.id = a.profile_id
  and p.auth_user_id = '10000000-0000-0000-0000-000000000001';

set local role authenticated;
select extensions.throws_ok(
  $$select public.submit_seller_application(
    '{"sellerType":"individual","firstName":"Test","lastName":"Applicant","birthDate":"1995-05-05","address":"Third address","identityDocumentType":"passport","payoutMethod":"bank","payoutAccountName":"Test Applicant","acceptedTermsVersion":"2026-10"}'::jsonb
  )$$,
  '23514',
  'an approved application cannot be resubmitted'
);
reset role;

-- Buyers remain unable to invoke legacy Seller operations.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',
  true
);
set local role authenticated;
select extensions.throws_ok(
  $$select public.create_product(
    '{"categoryId":1,"categoryGroup":"Art & Visual","categoryName":"Painting","productName":"Buyer test listing","description":"Must be denied","price":10,"stock":1,"image":"","tags":[],"pricingMode":"single","options":[]}'::jsonb
  )$$,
  '42501',
  'Buyers cannot create products'
);
select extensions.throws_ok(
  $$select public.create_follower_campaign(
    jsonb_build_object('type','fixed','value',1,'minimum',0,'maximum',1,
      'quantity',1,'valid_days',1,'starts_at',now(),
      'expires_at',now() + interval '1 day')
  )$$,
  '42501',
  'Buyers cannot create campaigns'
);
select extensions.throws_ok(
  $$insert into public.live_sessions (seller_id, broadcast_id, title, is_live)
    values (private.current_profile_id(), 'phase0-buyer-live', 'Must be denied', true)$$,
  '42501',
  'Buyers cannot create LIVE sessions'
);
reset role;

-- Active-Seller enforcement --------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}',
  true
);
set local role authenticated;
select extensions.throws_ok(
  $$select public.create_product(
    '{"categoryId":1,"categoryGroup":"Art & Visual","categoryName":"Painting","productName":"Unauthorized test listing","description":"Must be denied","price":10,"stock":1,"image":"","tags":[],"pricingMode":"single","options":[]}'::jsonb
  )$$,
  '42501',
  'inactive Sellers cannot create products'
);
select extensions.throws_ok(
  $$select public.create_follower_campaign(
    jsonb_build_object('type','fixed','value',1,'minimum',0,'maximum',1,
      'quantity',1,'valid_days',1,'starts_at',now(),
      'expires_at',now() + interval '1 day')
  )$$,
  '42501',
  'inactive Sellers cannot create campaigns'
);
select extensions.throws_ok(
  $$insert into public.live_sessions (seller_id, broadcast_id, title, is_live)
    values (private.current_profile_id(), 'phase0-unauthorized-live', 'Must be denied', true)$$,
  '42501',
  'inactive Sellers cannot create LIVE sessions'
);
select extensions.throws_ok(
  $$select public.update_my_shop_profile('Unauthorized Shop Rename', null, null)$$,
  '42501',
  'inactive Sellers cannot manage shop identity'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}',
  true
);
set local role authenticated;
select extensions.lives_ok(
  $$select public.update_my_shop_profile('Approved Test Shop', null, null)$$,
  'active Sellers can manage shop identity'
);
select extensions.lives_ok(
  $$select public.create_product(
    '{"categoryId":1,"categoryGroup":"Art & Visual","categoryName":"Painting","productName":"Approved seller listing","description":"Allowed","price":10,"stock":1,"image":"","tags":[],"pricingMode":"single","options":[]}'::jsonb
  )$$,
  'active Sellers can create products'
);
reset role;

-- Messaging and profile privacy boundaries. These assertions intentionally
-- expose the still-present legacy policy gaps.

insert into public.conversations (id, participant_ids)
select '20000000-0000-0000-0000-000000000001', array[p1.id, p2.id]
from public.profiles p1, public.profiles p2
where p1.auth_user_id = '10000000-0000-0000-0000-000000000001'
  and p2.auth_user_id = '10000000-0000-0000-0000-000000000004';
insert into public.messages (id, conversation_id, sender_id, receiver_id, message_text)
select '30000000-0000-0000-0000-000000000001',
       '20000000-0000-0000-0000-000000000001', p1.id, p2.id, 'Original'
from public.profiles p1, public.profiles p2
where p1.auth_user_id = '10000000-0000-0000-0000-000000000001'
  and p2.auth_user_id = '10000000-0000-0000-0000-000000000004';

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',
  true
);
set local role authenticated;
select extensions.throws_ok(
  $$update public.messages set message_text = 'Receiver rewrite', edited_at = now()
    where id = '30000000-0000-0000-0000-000000000001'$$,
  '42501',
  'a receiver cannot edit the sender message content'
);
select extensions.lives_ok(
  $$update public.messages set is_read = true
    where id = '30000000-0000-0000-0000-000000000001'$$,
  'a receiver can mark a received message as read'
);
select extensions.throws_ok(
  $$update public.conversations
    set participant_ids = array[private.current_profile_id(),
      (select id from public.profiles where auth_user_id = '10000000-0000-0000-0000-000000000005')]
    where id = '20000000-0000-0000-0000-000000000001'$$,
  '42501',
  'a participant cannot rewrite conversation membership'
);
select extensions.throws_ok(
  $$delete from public.messages
    where id = '30000000-0000-0000-0000-000000000001'$$,
  '42501',
  'a participant cannot directly delete message history'
);
select extensions.is(
  (select count(*)::integer from public.profiles
   where auth_user_id = '10000000-0000-0000-0000-000000000001'
     and email is not null),
  0,
  'an unrelated authenticated user cannot read another profile email'
);
select extensions.is(
  (select count(*)::integer from public.marketplace_profiles
   where id = (select id from public.profiles
     where auth_user_id = '10000000-0000-0000-0000-000000000001')),
  1,
  'an authenticated user can read safe marketplace identity fields'
);
reset role;

-- Exact-order helper fixtures ----------------------------------------------

insert into public.products
  (id, seller_id, category_id, product_name, description, price, stock, image)
select 900001, id, 1, 'Active seller item', 'Fixture', 10, 10, ''
from public.profiles where auth_user_id = '10000000-0000-0000-0000-000000000006';
insert into public.products
  (id, seller_id, category_id, product_name, description, price, stock, image)
select 900002, id, 1, 'Inactive seller item', 'Fixture', 10, 10, ''
from public.profiles where auth_user_id = '10000000-0000-0000-0000-000000000005';
insert into public.products
  (id, seller_id, category_id, product_name, description, price, stock, image)
select 900003, id, 1, 'Other seller item', 'Fixture', 10, 10, ''
from public.profiles where auth_user_id = '10000000-0000-0000-0000-000000000007';

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',
  true
);
set local role authenticated;
select extensions.throws_ok(
  $$select public.place_order(
    '{"items":[{"product_id":900002,"quantity":1}],"voucher_ids":{},"payment_method":"Cash on Delivery","delivery_address":{"fullName":"Buyer Two","phone":"09170000000","line1":"Test","city":"Test","province":"Test"}}'::jsonb
  )$$,
  '42501',
  'buyers cannot place a new order with an inactive Seller'
);
reset role;

insert into public.orders
  (id, customer_id, seller_ids, product_ids, subtotal, total, payment_method, delivery_address, status)
select 910001, buyer.id, array[active.id], array[900001], 10, 10,
       'Cash on Delivery', '{"fixture":true}', 'Pending'
from public.profiles buyer, public.profiles active
where buyer.auth_user_id = '10000000-0000-0000-0000-000000000004'
  and active.auth_user_id = '10000000-0000-0000-0000-000000000006';
insert into public.order_items
  (order_id, product_id, seller_id, quantity, item_price, product_name, status)
select 910001, 900001, id, 1, 10, 'Active seller item', 'Pending'
from public.profiles where auth_user_id = '10000000-0000-0000-0000-000000000006';

insert into public.orders
  (id, customer_id, seller_ids, product_ids, subtotal, total, payment_method, delivery_address, status)
select 910002, buyer.id, array[inactive.id], array[900002], 10, 10,
       'Cash on Delivery', '{"fixture":true}', 'Pending'
from public.profiles buyer, public.profiles inactive
where buyer.auth_user_id = '10000000-0000-0000-0000-000000000004'
  and inactive.auth_user_id = '10000000-0000-0000-0000-000000000005';
insert into public.order_items
  (order_id, product_id, seller_id, quantity, item_price, product_name, status)
select 910002, 900002, id, 1, 10, 'Inactive seller item', 'Pending'
from public.profiles where auth_user_id = '10000000-0000-0000-0000-000000000005';

insert into public.seller_order_fulfillment_grants
  (profile_id, order_id, granted_by, reason, created_at, expires_at)
select id, 910002, '10000000-0000-0000-0000-000000000001',
       'Disposable exact-order fixture', now() - interval '1 hour', now() + interval '1 hour'
from public.profiles where auth_user_id = '10000000-0000-0000-0000-000000000005';

-- A multi-seller order must authorize each Seller only while that Seller has
-- at least one nonterminal item. Other Sellers' item state is irrelevant.
insert into public.orders
  (id, customer_id, seller_ids, product_ids, subtotal, total, payment_method, delivery_address, status)
select 910003, buyer.id, array[active.id, other_seller.id],
       array[900001, 900003], 20, 20, 'Cash on Delivery',
       '{"fixture":true}', 'Preparing'
from public.profiles buyer, public.profiles active, public.profiles other_seller
where buyer.auth_user_id = '10000000-0000-0000-0000-000000000004'
  and active.auth_user_id = '10000000-0000-0000-0000-000000000006'
  and other_seller.auth_user_id = '10000000-0000-0000-0000-000000000007';
insert into public.order_items
  (order_id, product_id, seller_id, quantity, item_price, product_name, status)
select 910003, 900001, id, 1, 10, 'Active seller item', 'Delivered'
from public.profiles where auth_user_id = '10000000-0000-0000-0000-000000000006';
insert into public.order_items
  (order_id, product_id, seller_id, quantity, item_price, product_name, status)
select 910003, 900003, id, 1, 10, 'Other seller item', 'Pending'
from public.profiles where auth_user_id = '10000000-0000-0000-0000-000000000007';

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}',
  true
);
set local role authenticated;
select extensions.ok(private.can_fulfill_seller_order(910001),
  'active Seller may fulfill an owned nonterminal order');
select extensions.ok(not private.can_fulfill_seller_order(910002),
  'active Seller cannot fulfill an unrelated order');
select extensions.ok(not private.can_fulfill_seller_order(910003),
  'active Seller cannot fulfill a multi-seller order after its own items are Delivered');
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000007","role":"authenticated"}',
  true
);
set local role authenticated;
select extensions.ok(not private.can_fulfill_seller_order(910003),
  'an inactive Seller without an exact grant cannot fulfill its pending part of a multi-seller order');
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}',
  true
);
set local role authenticated;
select extensions.ok(private.can_fulfill_seller_order(910002),
  'inactive Seller may fulfill only an exact order with a valid transition grant');
select extensions.ok(not private.can_fulfill_seller_order(910001),
  'an exact-order grant does not authorize an unrelated order');
reset role;

update public.seller_order_fulfillment_grants
set revoked_at = now()
where order_id = 910002;
set local role authenticated;
select extensions.ok(not private.can_fulfill_seller_order(910002),
  'a revoked exact-order grant is denied');
reset role;

update public.seller_order_fulfillment_grants
set revoked_at = null,
    created_at = now() - interval '2 hours',
    expires_at = now() - interval '1 hour'
where order_id = 910002;
set local role authenticated;
select extensions.ok(not private.can_fulfill_seller_order(910002),
  'an expired exact-order grant is denied');
reset role;

-- A terminal order must be denied even if inconsistent legacy data still has
-- a nonterminal item. This currently exposes the missing order-status check.
update public.seller_order_fulfillment_grants
set created_at = now() - interval '1 hour', expires_at = now() + interval '1 hour'
where order_id = 910002;
update public.orders set status = 'Cancelled' where id = 910002;
set local role authenticated;
select extensions.ok(not private.can_fulfill_seller_order(910002),
  'a terminal order is denied even if an item is inconsistently nonterminal');
reset role;

-- service_role is expected to manage the server-owned authorization tables.
set local role service_role;
select extensions.lives_ok(
  $$update public.seller_accounts set status_reason = 'Service-role validation'
    where profile_id = (select id from public.profiles
      where auth_user_id = '10000000-0000-0000-0000-000000000006')$$,
  'service_role can perform trusted authorization-table maintenance'
);
reset role;

select * from extensions.finish();
rollback;
