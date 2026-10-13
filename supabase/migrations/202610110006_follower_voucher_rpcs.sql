create or replace function public.create_follower_campaign(config jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  seller_profile_id bigint := private.current_profile_id();
  existing public.follower_campaigns%rowtype;
  campaign_uuid uuid;
  discount_type text := config ->> 'type';
  discount_value numeric := (config ->> 'value')::numeric;
  minimum_value numeric := coalesce((config ->> 'minimum')::numeric, 0);
  maximum_value numeric := (config ->> 'maximum')::numeric;
  voucher_quantity integer := (config ->> 'quantity')::integer;
  validity_days integer := (config ->> 'valid_days')::integer;
  starts timestamptz := (config ->> 'starts_at')::timestamptz;
  expires timestamptz := (config ->> 'expires_at')::timestamptz;
begin
  if seller_profile_id is null or not private.is_seller() then
    raise exception 'Only sellers can create campaigns.' using errcode = '42501';
  end if;
  if discount_type not in ('percentage', 'fixed')
     or discount_value <= 0
     or (discount_type = 'percentage' and discount_value > 100)
     or minimum_value < 0
     or (maximum_value is not null and maximum_value <= 0)
     or voucher_quantity <= 0
     or validity_days not between 1 and 365
     or expires <= starts
     or expires <= now() then
    raise exception 'Invalid campaign configuration.' using errcode = '22023';
  end if;

  select * into existing from public.follower_campaigns
  where seller_id = seller_profile_id for update;
  if found and existing.status <> 'ended' and existing.expires_at > now() then
    raise exception 'End the current campaign before creating another.'
      using errcode = '23505';
  end if;

  if found then
    update public.follower_campaigns
    set campaign_id = gen_random_uuid()::text,
        type = discount_type,
        value = discount_value,
        minimum = minimum_value,
        maximum = maximum_value,
        quantity = voucher_quantity,
        claimed = 0,
        valid_days = validity_days,
        status = 'active',
        starts_at = starts,
        expires_at = expires,
        created_at = now()
    where seller_id = seller_profile_id
    returning id into campaign_uuid;
  else
    insert into public.follower_campaigns (
      campaign_id, seller_id, type, value, minimum, maximum, quantity,
      valid_days, starts_at, expires_at
    ) values (
      gen_random_uuid()::text, seller_profile_id, discount_type,
      discount_value, minimum_value, maximum_value, voucher_quantity,
      validity_days, starts, expires
    ) returning id into campaign_uuid;
  end if;
  return campaign_uuid;
end;
$$;

create or replace function public.toggle_shop_follow(target_seller_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  customer_profile_id bigint := private.current_profile_id();
  first_follow boolean;
  active_campaign public.follower_campaigns%rowtype;
  issued_voucher_id text;
  seller_display_name text;
begin
  if customer_profile_id is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;
  if customer_profile_id = target_seller_id or not exists (
    select 1 from public.profiles
    where id = target_seller_id and account_type = 'Seller'
  ) then
    raise exception 'Invalid seller.' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.shop_follows
    where follower_id = customer_profile_id and seller_id = target_seller_id
  ) then
    delete from public.shop_follows
    where follower_id = customer_profile_id and seller_id = target_seller_id;
    return jsonb_build_object('following', false, 'voucher_id', null);
  end if;

  insert into public.shop_follows (follower_id, seller_id)
  values (customer_profile_id, target_seller_id);

  insert into public.shop_follow_history (customer_id, seller_id)
  values (customer_profile_id, target_seller_id)
  on conflict do nothing
  returning true into first_follow;

  if coalesce(first_follow, false) then
    select * into active_campaign
    from public.follower_campaigns
    where seller_id = target_seller_id
      and status = 'active'
      and starts_at <= now()
      and expires_at > now()
      and claimed < quantity
    for update;

    if found then
      issued_voucher_id := gen_random_uuid()::text;
      select coalesce(nullif(trim(shop_name), ''), trim(first_name || ' ' || last_name), 'Shop')
      into seller_display_name from public.profiles where id = target_seller_id;

      insert into public.customer_vouchers (
        id, campaign_id, customer_id, seller_id, seller_name, type, value,
        minimum, maximum, expires_at
      ) values (
        issued_voucher_id, active_campaign.campaign_id, customer_profile_id,
        target_seller_id, seller_display_name, active_campaign.type,
        active_campaign.value, active_campaign.minimum, active_campaign.maximum,
        now() + make_interval(days => active_campaign.valid_days)
      );

      update public.follower_campaigns
      set claimed = claimed + 1 where id = active_campaign.id;
    end if;
  end if;

  return jsonb_build_object(
    'following', true,
    'voucher_id', issued_voucher_id
  );
end;
$$;

revoke all on function public.create_follower_campaign(jsonb) from public, anon;
revoke all on function public.toggle_shop_follow(bigint) from public, anon;
grant execute on function public.create_follower_campaign(jsonb) to authenticated;
grant execute on function public.toggle_shop_follow(bigint) to authenticated;
