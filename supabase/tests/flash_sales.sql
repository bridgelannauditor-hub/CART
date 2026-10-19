-- Marketing Centre flash sales.
--
-- Run only against a disposable local Supabase database:
--   supabase db reset
--   supabase test db supabase/tests/flash_sales.sql
--
-- Covers: client grants, eligibility reasons and the 30-day minimum discount,
-- schedule/stock/limit validation, ownership, one sale per product, the price
-- lock, checkout pricing with per-customer limits and promo stock, stale cart
-- handling, cancellations returning units, seller cancellation, and the
-- retired products.is_flash_sale flag. The transaction is rolled back.

begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

-- Fixtures ------------------------------------------------------------------
-- Profiles are created by the signup trigger as Customers; sellers are then
-- promoted with an active seller account.

insert into auth.users
  (id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('40000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'flash-seller@example.test', '', now(), '{}', '{"first_name":"Sela"}', now(), now()),
  ('40000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'flash-other-seller@example.test', '', now(), '{}', '{"first_name":"Otto"}', now(), now()),
  ('40000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'flash-customer@example.test', '', now(), '{}', '{"first_name":"Cora"}', now(), now()),
  ('40000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'flash-customer-two@example.test', '', now(), '{}', '{"first_name":"Dana"}', now(), now());

create temporary table ids (name text primary key, value bigint) on commit drop;
grant select on ids to authenticated;

insert into ids
select 'seller', id from public.profiles
where auth_user_id = '40000000-0000-0000-0000-000000000001'
union all
select 'other_seller', id from public.profiles
where auth_user_id = '40000000-0000-0000-0000-000000000002'
union all
select 'customer', id from public.profiles
where auth_user_id = '40000000-0000-0000-0000-000000000003'
union all
select 'customer_two', id from public.profiles
where auth_user_id = '40000000-0000-0000-0000-000000000004';

update public.profiles set account_type = 'Seller', shop_name = 'Flash Crafts',
  seller_tier = 2
where id in ((select value from ids where name = 'seller'),
             (select value from ids where name = 'other_seller'));
insert into public.seller_accounts (profile_id, status, approved_by, approved_at)
select value, 'active', '40000000-0000-0000-0000-000000000001', now()
from ids where name in ('seller', 'other_seller');

-- proven: single price, listed 20 days, delivered sale, price history below.
-- fresh: listed today, no sales.
-- pictures: per-picture prices with a 10% regular discount.
-- raised: regular price raised 3 days ago.
insert into public.products (seller_id, category_id, product_name, description,
  price, stock, discount_percent, pricing_mode, options, created_at)
values
  ((select value from ids where name = 'seller'), 1, 'Proven basket', 'x',
   1000, 50, 0, 'single', '[]', now() - interval '20 days'),
  ((select value from ids where name = 'seller'), 1, 'Fresh vase', 'x',
   1000, 50, 0, 'single', '[]', now()),
  ((select value from ids where name = 'seller'), 1, 'Picture tote', 'x',
   500, 20, 10, 'per_image',
   '[{"id":"red","name":"Red","image":"","price":500,"stock":10,"isDefault":true},
     {"id":"blue","name":"Blue","image":"","price":800,"stock":10,"isDefault":false}]',
   now() - interval '20 days'),
  ((select value from ids where name = 'seller'), 1, 'Raised lamp', 'x',
   1000, 50, 0, 'single', '[]', now() - interval '20 days');

insert into ids
select 'proven', id from public.products where product_name = 'Proven basket'
union all select 'fresh', id from public.products where product_name = 'Fresh vase'
union all select 'pictures', id from public.products where product_name = 'Picture tote'
union all select 'raised', id from public.products where product_name = 'Raised lamp';

-- Products record their current prices on insert. Date proven's insert-time
-- row to its listing date, then add older prices: 300 (50 days ago, superseded
-- before the window) and 900 (40 days ago, still in effect when the 30-day
-- window opened). raised was 800 three days ago and is 1000 now.
update public.product_price_history set recorded_at = now() - interval '20 days'
where product_id = (select value from ids where name = 'proven');
insert into public.product_price_history
  (product_id, price_key, regular_price, effective_price, recorded_at)
values
  ((select value from ids where name = 'proven'), '', 300, 300, now() - interval '50 days'),
  ((select value from ids where name = 'proven'), '', 900, 900, now() - interval '40 days'),
  ((select value from ids where name = 'raised'), '', 800, 800, now() - interval '3 days');

-- One delivered sale for proven, pictures and raised.
insert into public.orders (customer_id, seller_ids, product_ids, subtotal, total,
  status, payment_method, delivery_address)
values ((select value from ids where name = 'customer'),
  array[(select value from ids where name = 'seller')],
  array[(select value from ids where name = 'proven')],
  100, 100, 'Delivered', 'Cash on Delivery', '{}');
insert into public.order_items (order_id, product_id, seller_id, quantity,
  item_price, product_name, status)
select (select max(id) from public.orders), p.id, p.seller_id, 1, 100,
  p.product_name, 'Delivered'
from public.products p
where p.id in ((select value from ids where name = 'proven'),
               (select value from ids where name = 'pictures'),
               (select value from ids where name = 'raised'));

-- Catalog -------------------------------------------------------------------

select extensions.ok(
  (select bool_and(relrowsecurity) from pg_class
   where oid in ('public.flash_sales'::regclass,
                 'public.product_price_history'::regclass)),
  'flash_sales and product_price_history have RLS enabled'
);
select extensions.ok(
  has_table_privilege('authenticated', 'public.flash_sales', 'SELECT')
    and not has_table_privilege('authenticated', 'public.flash_sales', 'INSERT')
    and not has_table_privilege('authenticated', 'public.flash_sales', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.product_price_history', 'SELECT'),
  'clients read flash sales but cannot write them or read price history'
);
select extensions.ok(
  not has_function_privilege('authenticated', 'private.flash_sale_eligibility(bigint)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.create_flash_sale(jsonb)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.create_flash_sale(jsonb)', 'EXECUTE'),
  'only signed-in users can call the flash sale RPCs'
);
select extensions.ok(
  not has_column_privilege('authenticated', 'public.products', 'is_flash_sale', 'UPDATE')
    and has_column_privilege('authenticated', 'public.products', 'price', 'UPDATE'),
  'the retired is_flash_sale flag is no longer client-writable'
);

-- Eligibility ----------------------------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"40000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;

create temporary table eligibility on commit drop as
select value as item from jsonb_array_elements(public.my_flash_sale_eligibility());

select extensions.is(
  (select item -> 'reasons' from eligibility
   where (item ->> 'product_id')::bigint = (select value from ids where name = 'fresh')),
  '["Listed for less than 7 days.", "Needs at least 1 delivered sale."]'::jsonb,
  'a new product without delivered sales is not eligible'
);
select extensions.is(
  (select item -> 'reasons' from eligibility
   where (item ->> 'product_id')::bigint = (select value from ids where name = 'raised')),
  '["Regular price was raised in the last 7 days."]'::jsonb,
  'a recent price increase blocks a flash sale'
);
select extensions.is(
  (select (item ->> 'eligible')::boolean from eligibility
   where (item ->> 'product_id')::bigint = (select value from ids where name = 'proven')),
  true,
  'a product listed 20 days with a delivered sale is eligible'
);
select extensions.is(
  (select (item ->> 'min_discount_percent')::integer from eligibility
   where (item ->> 'product_id')::bigint = (select value from ids where name = 'proven')),
  11,
  'the minimum discount beats the 30-day low of 900, ignoring superseded prices'
);
select extensions.is(
  (select (item ->> 'min_discount_percent')::integer from eligibility
   where (item ->> 'product_id')::bigint = (select value from ids where name = 'pictures')),
  11,
  'per-picture prices must beat their own 10% regular discount'
);

-- Creating flash sales ---------------------------------------------------------

select extensions.throws_ok(
  format($$select public.create_flash_sale(jsonb_build_object(
    'product_id', %s, 'discount_percent', 20, 'promo_stock', 5,
    'per_customer_limit', 3, 'starts_at', now() + interval '2 hours',
    'ends_at', now() + interval '5 hours'))$$,
    (select value from ids where name = 'fresh')),
  '23514', 'Listed for less than 7 days.',
  'an ineligible product is rejected'
);
select extensions.throws_ok(
  format($$select public.create_flash_sale(jsonb_build_object(
    'product_id', %s, 'discount_percent', 10, 'promo_stock', 5,
    'per_customer_limit', 3, 'starts_at', now() + interval '2 hours',
    'ends_at', now() + interval '5 hours'))$$,
    (select value from ids where name = 'proven')),
  '22023', 'Choose a discount between 11 and 90 percent.',
  'a discount that does not beat the 30-day low is rejected'
);
select extensions.throws_ok(
  format($$select public.create_flash_sale(jsonb_build_object(
    'product_id', %s, 'discount_percent', 20, 'promo_stock', 51,
    'per_customer_limit', 3, 'starts_at', now() + interval '2 hours',
    'ends_at', now() + interval '5 hours'))$$,
    (select value from ids where name = 'proven')),
  '22023', 'Flash stock must be between 1 and 50.',
  'promo stock cannot exceed product stock'
);
select extensions.throws_ok(
  format($$select public.create_flash_sale(jsonb_build_object(
    'product_id', %s, 'discount_percent', 20, 'promo_stock', 5,
    'per_customer_limit', 11, 'starts_at', now() + interval '2 hours',
    'ends_at', now() + interval '5 hours'))$$,
    (select value from ids where name = 'proven')),
  '22023', 'The purchase limit must be between 1 and 10 per customer.',
  'the per-customer limit is capped at 10'
);
select extensions.throws_ok(
  format($$select public.create_flash_sale(jsonb_build_object(
    'product_id', %s, 'discount_percent', 20, 'promo_stock', 5,
    'per_customer_limit', 3, 'starts_at', now() + interval '10 minutes',
    'ends_at', now() + interval '3 hours'))$$,
    (select value from ids where name = 'proven')),
  '22023', 'Schedule the flash sale to start at least 1 hour from now.',
  'a flash sale must be scheduled at least 1 hour ahead'
);
select extensions.throws_ok(
  format($$select public.create_flash_sale(jsonb_build_object(
    'product_id', %s, 'discount_percent', 20, 'promo_stock', 5,
    'per_customer_limit', 3, 'starts_at', now() + interval '2 hours',
    'ends_at', now() + interval '80 hours'))$$,
    (select value from ids where name = 'proven')),
  '22023', 'A flash sale runs for 1 to 72 hours.',
  'a flash sale cannot run longer than 72 hours'
);
select extensions.lives_ok(
  format($$select public.create_flash_sale(jsonb_build_object(
    'product_id', %s, 'discount_percent', 20, 'promo_stock', 5,
    'per_customer_limit', 3, 'starts_at', now() + interval '2 hours',
    'ends_at', now() + interval '5 hours'))$$,
    (select value from ids where name = 'proven')),
  'an eligible product gets a scheduled flash sale'
);
select extensions.throws_ok(
  format($$select public.create_flash_sale(jsonb_build_object(
    'product_id', %s, 'discount_percent', 25, 'promo_stock', 5,
    'per_customer_limit', 3, 'starts_at', now() + interval '10 hours',
    'ends_at', now() + interval '12 hours'))$$,
    (select value from ids where name = 'proven')),
  '23514', 'Already has a scheduled or live flash sale.',
  'a product has at most one scheduled or live flash sale'
);
select extensions.lives_ok(
  format($$select public.create_flash_sale(jsonb_build_object(
    'product_id', %s, 'discount_percent', 30, 'promo_stock', 4,
    'per_customer_limit', 2, 'starts_at', now() + interval '2 hours',
    'ends_at', now() + interval '3 hours'))$$,
    (select value from ids where name = 'pictures')),
  'per-picture products can run a flash sale'
);

-- Price lock --------------------------------------------------------------------

select extensions.throws_ok(
  format('update public.products set price = 1200 where id = %s',
    (select value from ids where name = 'proven')),
  '23514', 'Cancel the flash sale before changing this product''s price or discount.',
  'the price is locked while a flash sale is scheduled'
);
select extensions.throws_ok(
  format('update public.products set discount_percent = 30 where id = %s',
    (select value from ids where name = 'proven')),
  '23514', 'Cancel the flash sale before changing this product''s price or discount.',
  'the regular discount is locked while a flash sale is scheduled'
);
select extensions.lives_ok(
  format('update public.products set description = %L where id = %s',
    'New description', (select value from ids where name = 'proven')),
  'other product details can still be edited'
);
select extensions.throws_ok(
  format('update public.products set is_flash_sale = true where id = %s',
    (select value from ids where name = 'fresh')),
  '42501', null,
  'sellers can no longer set the retired flag'
);

reset role;

-- Another seller cannot touch it.
select set_config('request.jwt.claims',
  '{"sub":"40000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select extensions.throws_ok(
  format($$select public.create_flash_sale(jsonb_build_object(
    'product_id', %s, 'discount_percent', 20, 'promo_stock', 5,
    'per_customer_limit', 3, 'starts_at', now() + interval '2 hours',
    'ends_at', now() + interval '5 hours'))$$,
    (select value from ids where name = 'fresh')),
  'P0002', 'Product not found.',
  'sellers cannot create flash sales for another shop'
);
select extensions.throws_ok(
  format('select public.cancel_flash_sale(%s)',
    (select id from public.flash_sales
     where product_id = (select value from ids where name = 'proven'))),
  '23514', 'This flash sale has already ended or was cancelled.',
  'sellers cannot cancel another shop''s flash sale'
);
reset role;

-- Make both sales live (now() is fixed for the whole transaction).
update public.flash_sales
set starts_at = now() - interval '1 minute', ends_at = now() + interval '2 hours';
insert into ids
select 'proven_sale', id from public.flash_sales
where product_id = (select value from ids where name = 'proven')
union all
select 'pictures_sale', id from public.flash_sales
where product_id = (select value from ids where name = 'pictures');

-- Checkout ------------------------------------------------------------------------

create function pg_temp.order_payload(items jsonb) returns jsonb language sql as $$
  select jsonb_build_object(
    'items', items, 'payment_method', 'Cash on Delivery',
    'delivery_address', jsonb_build_object('fullName', 'Cora', 'phone', '0917',
      'line1', '1 Street', 'city', 'Manila', 'province', 'Metro Manila'))
$$;
grant execute on function pg_temp.order_payload(jsonb) to authenticated;

select set_config('request.jwt.claims',
  '{"sub":"40000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
set local role authenticated;

select extensions.lives_ok(
  format($$select public.place_order(pg_temp.order_payload(jsonb_build_array(
    jsonb_build_object('product_id', %s, 'quantity', 2, 'flash_sale_id', %s))))$$,
    (select value from ids where name = 'proven'),
    (select value from ids where name = 'proven_sale')),
  'a customer buys 2 units at the flash price'
);
select extensions.is(
  (select item_price from public.order_items
   where flash_sale_id = (select value from ids where name = 'proven_sale')
   order by id limit 1),
  800.00::numeric(12,2),
  'the flash price replaces the regular price (1000 less 20%)'
);
select extensions.throws_ok(
  format($$select public.place_order(pg_temp.order_payload(jsonb_build_array(
    jsonb_build_object('product_id', %s, 'quantity', 2, 'flash_sale_id', %s))))$$,
    (select value from ids where name = 'proven'),
    (select value from ids where name = 'proven_sale')),
  '23514', 'The flash sale limit for Proven basket is 3 per customer.',
  'the per-customer limit counts earlier orders'
);
select extensions.lives_ok(
  format($$select public.place_order(pg_temp.order_payload(jsonb_build_array(
    jsonb_build_object('product_id', %s, 'quantity', 1))))$$,
    (select value from ids where name = 'proven')),
  'a cart without a flash sale id still gets the flash price within the limit'
);
select extensions.is(
  (select count(*)::integer from public.order_items
   where flash_sale_id = (select value from ids where name = 'proven_sale')),
  2,
  'both orders are linked to the flash sale'
);
select extensions.throws_ok(
  format($$select public.place_order(pg_temp.order_payload(jsonb_build_array(
    jsonb_build_object('product_id', %s, 'quantity', 1, 'flash_sale_id', 999999))))$$,
    (select value from ids where name = 'proven')),
  '23514', 'The flash sale for Proven basket has ended or sold out. Review your cart.',
  'a stale flash sale id blocks checkout'
);
select extensions.lives_ok(
  format($$select public.place_order(pg_temp.order_payload(jsonb_build_array(
    jsonb_build_object('product_id', %s, 'quantity', 1, 'option_id', 'blue',
      'flash_sale_id', %s))))$$,
    (select value from ids where name = 'pictures'),
    (select value from ids where name = 'pictures_sale')),
  'a per-picture option can be bought at the flash price'
);
select extensions.is(
  (select item_price from public.order_items
   where flash_sale_id = (select value from ids where name = 'pictures_sale')),
  560.00::numeric(12,2),
  'the flash discount replaces the regular discount on picture prices (800 less 30%)'
);
reset role;

select set_config('request.jwt.claims',
  '{"sub":"40000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
set local role authenticated;
select extensions.throws_ok(
  format($$select public.place_order(pg_temp.order_payload(jsonb_build_array(
    jsonb_build_object('product_id', %s, 'quantity', 3, 'flash_sale_id', %s))))$$,
    (select value from ids where name = 'proven'),
    (select value from ids where name = 'proven_sale')),
  '23514', 'Only 2 flash sale units of Proven basket are left.',
  'promo stock caps flash sale units'
);
select extensions.lives_ok(
  format($$select public.place_order(pg_temp.order_payload(jsonb_build_array(
    jsonb_build_object('product_id', %s, 'quantity', 2, 'flash_sale_id', %s))))$$,
    (select value from ids where name = 'proven'),
    (select value from ids where name = 'proven_sale')),
  'the last 2 promo units sell'
);
select extensions.throws_ok(
  format($$select public.place_order(pg_temp.order_payload(jsonb_build_array(
    jsonb_build_object('product_id', %s, 'quantity', 1, 'flash_sale_id', %s))))$$,
    (select value from ids where name = 'proven'),
    (select value from ids where name = 'proven_sale')),
  '23514', 'The flash sale for Proven basket has ended or sold out. Review your cart.',
  'a sold-out flash sale blocks a cart that expected it'
);
select extensions.lives_ok(
  format($$select public.place_order(pg_temp.order_payload(jsonb_build_array(
    jsonb_build_object('product_id', %s, 'quantity', 1))))$$,
    (select value from ids where name = 'proven')),
  'after a sell-out the product sells at the regular price'
);
select extensions.is(
  (select item_price from public.order_items
   where product_id = (select value from ids where name = 'proven')
   order by id desc limit 1),
  1000.00::numeric(12,2),
  'the regular price applies once promo stock is gone'
);
reset role;

select extensions.is(
  (select sold from public.flash_sales
   where id = (select value from ids where name = 'proven_sale')),
  5,
  'sold counts every flash unit'
);

-- Cancellations return units ---------------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"40000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select extensions.lives_ok(
  format('select public.cancel_order_item(%s, %s)',
    (select order_id from public.order_items
     where flash_sale_id = (select value from ids where name = 'proven_sale')
     order by id limit 1),
    (select id from public.order_items
     where flash_sale_id = (select value from ids where name = 'proven_sale')
     order by id limit 1)),
  'the customer cancels their first flash purchase'
);
reset role;
select extensions.is(
  (select sold from public.flash_sales
   where id = (select value from ids where name = 'proven_sale')),
  3,
  'a customer cancellation returns its units to the flash sale'
);

select set_config('request.jwt.claims',
  '{"sub":"40000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select extensions.lives_ok(
  format($$select public.update_seller_order(%s, 'Cancelled')$$,
    (select o.id from public.orders o
     join public.order_items oi on oi.order_id = o.id
     where oi.flash_sale_id = (select value from ids where name = 'proven_sale')
       and o.customer_id = (select value from ids where name = 'customer_two'))),
  'the seller cancels the second customer''s flash order'
);
reset role;
select extensions.is(
  (select sold from public.flash_sales
   where id = (select value from ids where name = 'proven_sale')),
  1,
  'a seller cancellation returns its units to the flash sale'
);

-- Price history ---------------------------------------------------------------

select extensions.is(
  (select count(*)::integer from public.product_price_history
   where product_id = (select value from ids where name = 'pictures')),
  2,
  'option stock changes at checkout do not add price history'
);

-- Seller cancellation ---------------------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"40000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select extensions.lives_ok(
  format('select public.cancel_flash_sale(%s)',
    (select value from ids where name = 'proven_sale')),
  'the seller cancels a live flash sale'
);
select extensions.throws_ok(
  format('select public.cancel_flash_sale(%s)',
    (select value from ids where name = 'proven_sale')),
  '23514', 'This flash sale has already ended or was cancelled.',
  'a cancelled flash sale cannot be cancelled again'
);
select extensions.lives_ok(
  format('update public.products set price = 1200 where id = %s',
    (select value from ids where name = 'proven')),
  'the price unlocks once the flash sale is cancelled'
);
reset role;
select extensions.is(
  (select regular_price from public.product_price_history
   where product_id = (select value from ids where name = 'proven')
   order by recorded_at desc, id desc limit 1),
  1200.00::numeric(12,2),
  'a price change is recorded in price history'
);

select * from extensions.finish();
rollback;
