create or replace function private.recalculate_order(target_order_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  order_row public.orders%rowtype;
  applied jsonb;
  voucher_row public.customer_vouchers%rowtype;
  seller_subtotal numeric;
  voucher_discount numeric;
  new_vouchers jsonb := '[]'::jsonb;
  subtotal_value numeric;
  discount_value numeric := 0;
  aggregate_status text;
begin
  select * into order_row from public.orders where id = target_order_id for update;
  select coalesce(sum(quantity * item_price), 0) into subtotal_value
  from public.order_items where order_id = target_order_id and status <> 'Cancelled';

  for applied in select value from jsonb_array_elements(order_row.vouchers)
  loop
    select * into voucher_row from public.customer_vouchers
    where id = applied ->> 'voucherId' for update;
    select coalesce(sum(quantity * item_price), 0) into seller_subtotal
    from public.order_items
    where order_id = target_order_id
      and seller_id = (applied ->> 'sellerId')::bigint
      and status <> 'Cancelled';
    if seller_subtotal <= 0 or not found then
      update public.customer_vouchers
      set order_id = null, redeemed_at = null, revenue = 0
      where id = applied ->> 'voucherId';
      continue;
    end if;
    if voucher_row.type = 'percentage' then
      voucher_discount := seller_subtotal * voucher_row.value / 100;
      if voucher_row.maximum is not null then
        voucher_discount := least(voucher_discount, voucher_row.maximum);
      end if;
    else
      voucher_discount := voucher_row.value;
    end if;
    voucher_discount := round(least(voucher_discount, seller_subtotal), 2);
    discount_value := discount_value + voucher_discount;
    new_vouchers := new_vouchers || jsonb_build_array(jsonb_build_object(
      'voucherId', voucher_row.id,
      'sellerId', voucher_row.seller_id,
      'discount', voucher_discount
    ));
    update public.customer_vouchers
    set revenue = round(seller_subtotal - voucher_discount, 2)
    where id = voucher_row.id;
  end loop;

  select case
    when count(*) filter (where status <> 'Cancelled') = 0 then 'Cancelled'
    when count(*) filter (where status <> 'Cancelled') =
         count(*) filter (where status = 'Delivered') then 'Delivered'
    when count(*) filter (where status = 'Out for Delivery') > 0 then 'Out for Delivery'
    when count(*) filter (where status = 'Shipped') > 0 then 'Shipped'
    when count(*) filter (where status = 'Preparing') > 0 then 'Preparing'
    else 'Pending' end
  into aggregate_status from public.order_items where order_id = target_order_id;

  update public.orders set
    subtotal = round(subtotal_value, 2),
    discount = round(discount_value, 2),
    total = round(greatest(subtotal_value - discount_value, 0), 2),
    vouchers = new_vouchers,
    status = aggregate_status
  where id = target_order_id;
end;
$$;

create or replace function public.place_order(payload jsonb)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  customer_profile public.profiles%rowtype;
  requested jsonb;
  product_row public.products%rowtype;
  option_row jsonb;
  updated_options jsonb;
  item_price numeric;
  requested_quantity integer;
  requested_option text;
  line_items jsonb := '[]'::jsonb;
  seller_list bigint[] := '{}';
  product_list bigint[] := '{}';
  subtotal_value numeric := 0;
  discount_value numeric := 0;
  seller_subtotal numeric;
  voucher_discount numeric;
  voucher_pair record;
  voucher_row public.customer_vouchers%rowtype;
  applied_vouchers jsonb := '[]'::jsonb;
  fulfillment jsonb := '{}'::jsonb;
  tracking_value jsonb;
  created_order_id bigint;
  line_item jsonb;
  seller_id_value bigint;
  seller_profile public.profiles%rowtype;
  now_text text := now()::text;
begin
  select * into customer_profile from public.profiles
  where auth_user_id = auth.uid() and account_type = 'Customer';
  if not found then raise exception 'A customer account is required.' using errcode = '42501'; end if;
  if jsonb_typeof(payload -> 'items') <> 'array'
     or jsonb_array_length(payload -> 'items') not between 1 and 30 then
    raise exception 'Choose between 1 and 30 products.' using errcode = '22023';
  end if;
  if payload ->> 'payment_method' not in ('Cash on Delivery', 'GCash', 'Maya', 'Bank Account') then
    raise exception 'Unsupported payment method.' using errcode = '22023';
  end if;
  if coalesce(trim(payload #>> '{delivery_address,fullName}'), '') = ''
     or coalesce(trim(payload #>> '{delivery_address,phone}'), '') = ''
     or coalesce(trim(payload #>> '{delivery_address,line1}'), '') = ''
     or coalesce(trim(payload #>> '{delivery_address,city}'), '') = ''
     or coalesce(trim(payload #>> '{delivery_address,province}'), '') = '' then
    raise exception 'A complete delivery address is required.' using errcode = '22023';
  end if;

  for requested in select value from jsonb_array_elements(payload -> 'items')
  loop
    requested_quantity := (requested ->> 'quantity')::integer;
    requested_option := nullif(trim(requested ->> 'option_id'), '');
    if requested_quantity not between 1 and 99 then
      raise exception 'Invalid product quantity.' using errcode = '22023';
    end if;
    select * into product_row from public.products
    where id = (requested ->> 'product_id')::bigint for update;
    if not found then raise exception 'A selected product is unavailable.' using errcode = 'P0002'; end if;

    select * into seller_profile from public.profiles
    where id = product_row.seller_id and account_type = 'Seller';
    if not found then raise exception 'A seller account is unavailable.' using errcode = 'P0002'; end if;

    option_row := null;
    if product_row.pricing_mode = 'per_image' and jsonb_array_length(product_row.options) > 0 then
      select value into option_row from jsonb_array_elements(product_row.options)
      where value ->> 'id' = requested_option limit 1;
      if option_row is null then raise exception 'Choose an available product option.' using errcode = '22023'; end if;
      if (option_row ->> 'stock')::integer < requested_quantity then
        raise exception '% does not have enough stock.', product_row.product_name using errcode = '23514';
      end if;
      item_price := (option_row ->> 'price')::numeric;
      select jsonb_agg(case when value ->> 'id' = requested_option
        then jsonb_set(value, '{stock}', to_jsonb((value ->> 'stock')::integer - requested_quantity))
        else value end) into updated_options
      from jsonb_array_elements(product_row.options);
      update public.products set options = updated_options,
        stock = (select coalesce(sum((value ->> 'stock')::integer), 0)
                 from jsonb_array_elements(updated_options)),
        total_sold = total_sold + requested_quantity
      where id = product_row.id;
    else
      if requested_option is not null then raise exception 'This product option is unavailable.' using errcode = '22023'; end if;
      if product_row.stock < requested_quantity then
        raise exception '% does not have enough stock.', product_row.product_name using errcode = '23514';
      end if;
      item_price := product_row.price;
      update public.products set stock = stock - requested_quantity,
        total_sold = total_sold + requested_quantity where id = product_row.id;
    end if;

    line_items := line_items || jsonb_build_array(jsonb_build_object(
      'product_id', product_row.id, 'seller_id', product_row.seller_id,
      'quantity', requested_quantity, 'item_price', round(item_price, 2),
      'product_name', product_row.product_name,
      'product_image', coalesce(option_row ->> 'image', product_row.image, ''),
      'option_id', option_row ->> 'id', 'option_name', option_row ->> 'name',
      'option_image', option_row ->> 'image'
    ));
    subtotal_value := subtotal_value + item_price * requested_quantity;
    if array_position(seller_list, product_row.seller_id) is null then
      seller_list := array_append(seller_list, product_row.seller_id);
    end if;
    product_list := array_append(product_list, product_row.id);
  end loop;

  for voucher_pair in select * from jsonb_each_text(coalesce(payload -> 'voucher_ids', '{}'::jsonb))
  loop
    seller_id_value := voucher_pair.key::bigint;
    if array_position(seller_list, seller_id_value) is null then
      raise exception 'Voucher does not match this order.' using errcode = '23514';
    end if;
    select * into voucher_row from public.customer_vouchers
    where id = voucher_pair.value for update;
    if not found or voucher_row.customer_id <> customer_profile.id
       or voucher_row.seller_id <> seller_id_value or voucher_row.order_id is not null
       or voucher_row.expires_at <= now() then
      raise exception 'Voucher is expired, used, or unavailable.' using errcode = '23514';
    end if;
    select coalesce(sum((value ->> 'item_price')::numeric * (value ->> 'quantity')::integer), 0)
    into seller_subtotal from jsonb_array_elements(line_items)
    where (value ->> 'seller_id')::bigint = seller_id_value;
    if seller_subtotal < voucher_row.minimum then
      raise exception 'Voucher minimum purchase was not reached.' using errcode = '23514';
    end if;
    if voucher_row.type = 'percentage' then
      voucher_discount := seller_subtotal * voucher_row.value / 100;
      if voucher_row.maximum is not null then voucher_discount := least(voucher_discount, voucher_row.maximum); end if;
    else voucher_discount := voucher_row.value;
    end if;
    voucher_discount := round(least(voucher_discount, seller_subtotal), 2);
    discount_value := discount_value + voucher_discount;
    applied_vouchers := applied_vouchers || jsonb_build_array(jsonb_build_object(
      'voucherId', voucher_row.id, 'sellerId', seller_id_value, 'discount', voucher_discount));
  end loop;

  tracking_value := jsonb_build_object(
    'courier', '', 'trackingNumber', '', 'estimatedDeliveryDate', '',
    'currentLocation', 'Order placed', 'lastUpdated', now_text,
    'history', jsonb_build_array(jsonb_build_object(
      'status', 'Pending', 'location', 'Order placed', 'date', now_text)));
  foreach seller_id_value in array seller_list loop
    select coalesce(sum((value ->> 'item_price')::numeric * (value ->> 'quantity')::integer), 0)
    into seller_subtotal from jsonb_array_elements(line_items)
    where (value ->> 'seller_id')::bigint = seller_id_value;
    select coalesce(sum((value ->> 'discount')::numeric), 0) into voucher_discount
    from jsonb_array_elements(applied_vouchers)
    where (value ->> 'sellerId')::bigint = seller_id_value;
    fulfillment := jsonb_set(fulfillment, array[seller_id_value::text], jsonb_build_object(
      'status', 'Pending', 'subtotal', round(seller_subtotal, 2),
      'discount', round(voucher_discount, 2),
      'total', round(seller_subtotal - voucher_discount, 2), 'tracking', tracking_value));
  end loop;

  insert into public.orders (
    customer_id, seller_ids, product_ids, subtotal, discount, total, status,
    payment_method, delivery_address, seller_fulfillment, tracking, vouchers
  ) values (
    customer_profile.id, seller_list, product_list, round(subtotal_value, 2),
    round(discount_value, 2), round(subtotal_value - discount_value, 2), 'Pending',
    payload ->> 'payment_method', payload -> 'delivery_address', fulfillment,
    tracking_value, applied_vouchers
  ) returning id into created_order_id;

  for line_item in select value from jsonb_array_elements(line_items) loop
    insert into public.order_items (
      order_id, product_id, seller_id, quantity, item_price, product_name,
      product_image, option_id, option_name, option_image
    ) values (
      created_order_id, (line_item ->> 'product_id')::bigint,
      (line_item ->> 'seller_id')::bigint, (line_item ->> 'quantity')::integer,
      (line_item ->> 'item_price')::numeric, line_item ->> 'product_name',
      coalesce(line_item ->> 'product_image', ''), line_item ->> 'option_id',
      line_item ->> 'option_name', line_item ->> 'option_image');
  end loop;
  for line_item in select value from jsonb_array_elements(applied_vouchers) loop
    update public.customer_vouchers set order_id = created_order_id,
      redeemed_at = now(),
      revenue = (select round(coalesce(sum(quantity * item_price), 0) - (line_item ->> 'discount')::numeric, 2)
                 from public.order_items where order_id = created_order_id
                   and seller_id = (line_item ->> 'sellerId')::bigint)
    where id = line_item ->> 'voucherId';
  end loop;
  foreach seller_id_value in array seller_list loop
    if coalesce((select (notification_preferences ->> 'pushEnabled')::boolean
                 from public.profiles where id = seller_id_value), true)
       and coalesce((select (notification_preferences ->> 'orderUpdates')::boolean
                     from public.profiles where id = seller_id_value), true) then
      insert into public.notifications (user_id, created_by_id, title, body, type, related_id)
      values (seller_id_value, customer_profile.id, 'New order received',
        'Order #' || created_order_id || ' contains products from your shop.',
        'order', created_order_id);
    end if;
  end loop;
  return created_order_id;
end;
$$;

create or replace function public.cancel_order_item(target_order_id bigint, target_item_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id bigint := private.current_profile_id();
  item_row public.order_items%rowtype;
  product_row public.products%rowtype;
  updated_options jsonb;
begin
  select oi.* into item_row from public.order_items oi
  join public.orders o on o.id = oi.order_id
  where oi.id = target_item_id and oi.order_id = target_order_id
    and o.customer_id = caller_id for update of oi;
  if not found then raise exception 'Order item not found.' using errcode = 'P0002'; end if;
  if item_row.status <> 'Pending' then
    raise exception 'Only pending products can be cancelled.' using errcode = '23514';
  end if;
  update public.order_items set status = 'Cancelled', cancelled_at = now()
  where id = target_item_id;
  select * into product_row from public.products where id = item_row.product_id for update;
  if found and product_row.pricing_mode = 'per_image' and item_row.option_id is not null then
    select jsonb_agg(case when value ->> 'id' = item_row.option_id
      then jsonb_set(value, '{stock}', to_jsonb((value ->> 'stock')::integer + item_row.quantity))
      else value end) into updated_options from jsonb_array_elements(product_row.options);
    update public.products set options = updated_options,
      stock = (select coalesce(sum((value ->> 'stock')::integer), 0) from jsonb_array_elements(updated_options)),
      total_sold = greatest(total_sold - item_row.quantity, 0) where id = product_row.id;
  elsif found then
    update public.products set stock = stock + item_row.quantity,
      total_sold = greatest(total_sold - item_row.quantity, 0) where id = product_row.id;
  end if;
  perform private.recalculate_order(target_order_id);
  insert into public.notifications (user_id, created_by_id, title, body, type, related_id)
  select item_row.seller_id, caller_id, 'Product cancelled from order #' || target_order_id,
    'The customer cancelled "' || item_row.product_name || '".', 'order', target_order_id
  where coalesce((select (notification_preferences ->> 'pushEnabled')::boolean
                  from public.profiles where id = item_row.seller_id), true)
    and coalesce((select (notification_preferences ->> 'orderUpdates')::boolean
                  from public.profiles where id = item_row.seller_id), true);
end;
$$;

create or replace function public.update_seller_order(
  target_order_id bigint,
  new_status text,
  tracking_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  seller_profile public.profiles%rowtype;
  order_row public.orders%rowtype;
  previous_status text;
  item_row public.order_items%rowtype;
  product_row public.products%rowtype;
  updated_options jsonb;
  seller_tracking jsonb;
  seller_record jsonb;
  fulfillment jsonb;
  history jsonb;
  now_text text := now()::text;
begin
  select * into seller_profile from public.profiles
  where auth_user_id = auth.uid() and account_type = 'Seller';
  if not found then raise exception 'A seller account is required.' using errcode = '42501'; end if;
  select * into order_row from public.orders where id = target_order_id
    and seller_profile.id = any(seller_ids) for update;
  if not found then raise exception 'Order not found.' using errcode = 'P0002'; end if;
  select status into previous_status from public.order_items
  where order_id = target_order_id and seller_id = seller_profile.id and status <> 'Cancelled'
  limit 1;
  if previous_status is null then raise exception 'No active products remain.' using errcode = '23514'; end if;
  if new_status <> previous_status and not (
    (previous_status = 'Pending' and new_status in ('Preparing', 'Cancelled')) or
    (previous_status = 'Preparing' and new_status in ('Shipped', 'Cancelled')) or
    (previous_status = 'Shipped' and new_status = 'Out for Delivery') or
    (previous_status = 'Out for Delivery' and new_status = 'Delivered')
  ) then raise exception 'Invalid order status transition.' using errcode = '23514'; end if;

  if new_status = 'Cancelled' then
    for item_row in select * from public.order_items
      where order_id = target_order_id and seller_id = seller_profile.id and status <> 'Cancelled'
    loop
      select * into product_row from public.products where id = item_row.product_id for update;
      if product_row.pricing_mode = 'per_image' and item_row.option_id is not null then
        select jsonb_agg(case when value ->> 'id' = item_row.option_id
          then jsonb_set(value, '{stock}', to_jsonb((value ->> 'stock')::integer + item_row.quantity))
          else value end) into updated_options from jsonb_array_elements(product_row.options);
        update public.products set options = updated_options,
          stock = (select coalesce(sum((value ->> 'stock')::integer), 0) from jsonb_array_elements(updated_options)),
          total_sold = greatest(total_sold - item_row.quantity, 0) where id = product_row.id;
      else
        update public.products set stock = stock + item_row.quantity,
          total_sold = greatest(total_sold - item_row.quantity, 0) where id = product_row.id;
      end if;
    end loop;
  end if;
  update public.order_items set status = new_status,
    cancelled_at = case when new_status = 'Cancelled' then now() else cancelled_at end
  where order_id = target_order_id and seller_id = seller_profile.id and status <> 'Cancelled';

  fulfillment := order_row.seller_fulfillment;
  seller_record := coalesce(fulfillment -> seller_profile.id::text, '{}'::jsonb);
  seller_tracking := coalesce(seller_record -> 'tracking', '{}'::jsonb);
  history := coalesce(seller_tracking -> 'history', '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object('status', new_status,
      'location', coalesce(tracking_data ->> 'currentLocation', ''), 'date', now_text));
  seller_tracking := seller_tracking || tracking_data || jsonb_build_object(
    'lastUpdated', now_text, 'history', history);
  seller_record := seller_record || jsonb_build_object(
    'status', new_status, 'tracking', seller_tracking);
  fulfillment := jsonb_set(fulfillment, array[seller_profile.id::text], seller_record);
  update public.orders set seller_fulfillment = fulfillment,
    tracking = tracking || jsonb_build_object(
      'currentLocation', coalesce(tracking_data ->> 'currentLocation', ''),
      'lastUpdated', now_text,
      'history', coalesce(tracking -> 'history', '[]'::jsonb) || jsonb_build_array(
        jsonb_build_object('status', new_status,
          'location', coalesce(tracking_data ->> 'currentLocation', ''),
          'date', now_text, 'sellerId', seller_profile.id)))
  where id = target_order_id;
  perform private.recalculate_order(target_order_id);
  insert into public.notifications (user_id, created_by_id, title, body, type, related_id)
  select order_row.customer_id, seller_profile.id, 'Order #' || target_order_id || ' update',
    coalesce(nullif(seller_profile.shop_name, ''), 'A seller') ||
      ' marked their products as "' || new_status || '".',
    'order_status', target_order_id
  where coalesce((select (notification_preferences ->> 'pushEnabled')::boolean
                  from public.profiles where id = order_row.customer_id), true)
    and coalesce((select (notification_preferences ->> 'orderUpdates')::boolean
                  from public.profiles where id = order_row.customer_id), true);
end;
$$;

revoke all on function public.place_order(jsonb) from public, anon;
revoke all on function public.cancel_order_item(bigint, bigint) from public, anon;
revoke all on function public.update_seller_order(bigint, text, jsonb) from public, anon;
grant execute on function public.place_order(jsonb) to authenticated;
grant execute on function public.cancel_order_item(bigint, bigint) to authenticated;
grant execute on function public.update_seller_order(bigint, text, jsonb) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'orders'
  ) then alter publication supabase_realtime add table public.orders; end if;
end;
$$;
