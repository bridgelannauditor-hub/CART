-- Enforce the reviewed seller boundary and close the Phase 0 profile/chat gaps.
-- Apply only after approved sellers have seller_accounts rows and reviewed
-- legacy orders have exact fulfillment grants where required.

begin;

-- Public marketplace identity is a deliberately small projection. Private
-- contact, Auth-linking, and verification evidence remain in profiles.
drop view if exists public.marketplace_profiles;
create view public.marketplace_profiles as
select
  id, first_name, last_name, account_type, shop_name, cover_image,
  profile_image, is_live, is_verified_seller, seller_tier, trust_score,
  created_at
from public.profiles;

revoke all on public.marketplace_profiles from public, anon, authenticated;
grant select on public.marketplace_profiles to authenticated;

drop policy if exists profiles_read_authenticated on public.profiles;
drop policy if exists profiles_read_private on public.profiles;
create policy profiles_read_private on public.profiles
for select to authenticated
using (
  auth_user_id = (select auth.uid())
  or (select private.is_admin())
);

-- The compatibility helper now means approved and active, not merely a legacy
-- profile carrying account_type = Seller.
create or replace function private.is_seller()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_active_seller_authorization(private.current_profile_id());
$$;

revoke all on function private.is_seller() from public, anon, authenticated;
grant execute on function private.is_seller() to authenticated, service_role;

-- create_product is SECURITY DEFINER, so RLS alone does not constrain it.
create or replace function private.enforce_active_seller_product_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('role', true) in ('authenticated', 'anon')
     and not private.has_active_seller_authorization(new.seller_id) then
    raise exception 'Seller approval is required before publishing products.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_active_seller_product_insert on public.products;
create trigger enforce_active_seller_product_insert
before insert on public.products
for each row execute function private.enforce_active_seller_product_insert();

-- Checkout must not create new order items for an inactive seller. A failure
-- rolls the order transaction back, including stock changes.
create or replace function private.enforce_active_seller_order_item_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('role', true) in ('authenticated', 'anon')
     and not private.has_active_seller_authorization(new.seller_id) then
    raise exception 'This shop is not accepting new orders.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_active_seller_order_item_insert on public.order_items;
create trigger enforce_active_seller_order_item_insert
before insert on public.order_items
for each row execute function private.enforce_active_seller_order_item_insert();

-- Seller fulfillment requires active authorization or one reviewed exact-order
-- transition grant. Buyer cancellation follows a separate path.
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
    raise exception 'Seller approval is required to fulfil this order.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_active_seller_fulfillment on public.order_items;
create trigger enforce_active_seller_fulfillment
before update on public.order_items
for each row execute function private.enforce_active_seller_fulfillment();

-- New follows and vouchers cannot target an inactive shop.
create or replace function private.enforce_active_follow_target()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('role', true) in ('authenticated', 'anon')
     and not private.has_active_seller_authorization(new.seller_id) then
    raise exception 'This shop is not currently available.' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_active_follow_target on public.shop_follows;
create trigger enforce_active_follow_target
before insert on public.shop_follows
for each row execute function private.enforce_active_follow_target();

-- Only a caller-bound function may change the denormalized LIVE flag.
revoke update (is_live) on public.profiles from authenticated;
create or replace function public.set_my_live_status(new_is_live boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id bigint := private.current_profile_id();
begin
  if caller_id is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;
  if new_is_live and not private.has_active_seller_authorization(caller_id) then
    raise exception 'Seller approval is required before starting LIVE.'
      using errcode = '42501';
  end if;
  update public.profiles set is_live = new_is_live where id = caller_id;
end;
$$;
revoke all on function public.set_my_live_status(boolean)
  from public, anon, authenticated;
grant execute on function public.set_my_live_status(boolean) to authenticated;

-- Shop identity fields are Seller capabilities, not general profile fields.
revoke update (shop_name, cover_image, profile_image)
  on public.profiles from authenticated;
create or replace function public.update_my_shop_profile(
  new_shop_name text default null,
  new_cover_image text default null,
  new_profile_image text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id bigint := private.current_profile_id();
  clean_name text := nullif(trim(new_shop_name), '');
begin
  if caller_id is null
     or not private.has_active_seller_authorization(caller_id) then
    raise exception 'Active Seller approval is required to manage a shop.'
      using errcode = '42501';
  end if;
  if new_shop_name is not null and (
       clean_name is null
       or char_length(clean_name) not between 3 and 60
       or clean_name !~ '^[[:alnum:]][[:alnum:] &''.,-]*$'
     ) then
    raise exception 'Shop name must be 3-60 letters, numbers, or simple punctuation.'
      using errcode = '22023';
  end if;
  if char_length(coalesce(new_cover_image, '')) > 2048
     or char_length(coalesce(new_profile_image, '')) > 2048 then
    raise exception 'Shop image URL is too long.' using errcode = '22023';
  end if;
  update public.profiles
  set shop_name = coalesce(clean_name, shop_name),
      cover_image = coalesce(new_cover_image, cover_image),
      profile_image = coalesce(new_profile_image, profile_image)
  where id = caller_id;
end;
$$;
revoke all on function public.update_my_shop_profile(text, text, text)
  from public, anon, authenticated;
grant execute on function public.update_my_shop_profile(text, text, text)
  to authenticated;

-- Direct-message membership is canonical at creation and immutable afterward.
create or replace function private.enforce_conversation_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id bigint := private.current_profile_id();
  latest_message public.messages%rowtype;
  expected_preview text;
begin
  if current_setting('role', true) not in ('authenticated', 'anon') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if cardinality(new.participant_ids) <> 2
       or new.participant_ids[1] >= new.participant_ids[2]
       or caller_id is null
       or caller_id <> all(new.participant_ids)
       or (select count(*) from public.profiles p where p.id = any(new.participant_ids)) <> 2 then
      raise exception 'Invalid conversation participants.' using errcode = '42501';
    end if;
  else
    if new.participant_ids is distinct from old.participant_ids then
      raise exception 'Conversation membership cannot be changed.' using errcode = '42501';
    end if;
    if new.last_message is distinct from old.last_message
       or new.last_message_date is distinct from old.last_message_date then
      select * into latest_message
      from public.messages m
      where m.conversation_id = new.id
      order by m.message_date desc, m.id desc
      limit 1;
      expected_preview := case
        when nullif(trim(latest_message.message_text), '') is not null
          then latest_message.message_text
        when latest_message.message_type = 'image' then 'Photo'
        when latest_message.message_type = 'video' then 'Video'
        when latest_message.message_type = 'audio' then 'Voice message'
        else 'Message'
      end;
      if not found
         or new.last_message is distinct from expected_preview
         or new.last_message_date is distinct from latest_message.message_date then
        raise exception 'Conversation summaries are server-derived.' using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_conversation_membership on public.conversations;
create trigger enforce_conversation_membership
before insert or update on public.conversations
for each row execute function private.enforce_conversation_membership();

-- A sender may edit content; a receiver may only advance is_read to true.
create or replace function private.enforce_message_update_boundary()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id bigint := private.current_profile_id();
begin
  if current_setting('role', true) not in ('authenticated', 'anon') then
    return new;
  end if;
  if caller_id = old.sender_id then
    if (to_jsonb(new) - 'message_text' - 'edited_at')
         is distinct from (to_jsonb(old) - 'message_text' - 'edited_at')
       or char_length(trim(new.message_text)) not between 1 and 4000 then
      raise exception 'Senders may edit only message content.' using errcode = '42501';
    end if;
    new.edited_at := now();
  elsif caller_id = old.receiver_id then
    if (to_jsonb(new) - 'is_read') is distinct from (to_jsonb(old) - 'is_read')
       or new.is_read is not true then
      raise exception 'Recipients may only mark messages as read.' using errcode = '42501';
    end if;
  else
    raise exception 'Message update is not allowed.' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_message_update_boundary on public.messages;
create trigger enforce_message_update_boundary
before update on public.messages
for each row execute function private.enforce_message_update_boundary();

-- Identity evidence belongs to the exact identity facts that were verified.
create or replace function private.invalidate_changed_identity_evidence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if row(
       new.seller_type, new.birth_date, new.address,
       new.identity_document_type, new.organization_name,
       new.business_registration_number, new.business_type,
       new.business_tax_id, new.business_address, new.representative_role
     ) is distinct from row(
       old.seller_type, old.birth_date, old.address,
       old.identity_document_type, old.organization_name,
       old.business_registration_number, old.business_type,
       old.business_tax_id, old.business_address, old.representative_role
     ) then
    new.identity_status := 'not_started';
    new.identity_attempts := 0;
    new.identity_reason_code := null;
    new.identity_verified_at := null;
    new.identity_capture_completed := false;
    new.face_capture_completed := false;
  end if;
  if new.school_email is distinct from old.school_email then
    new.school_email_verified := false;
    new.credential_expiry := null;
  end if;
  return new;
end;
$$;

drop trigger if exists invalidate_changed_identity_evidence
  on public.seller_verification_applications;
create trigger invalidate_changed_identity_evidence
before update on public.seller_verification_applications
for each row execute function private.invalidate_changed_identity_evidence();

revoke all on function private.enforce_active_seller_product_insert()
  from public, anon, authenticated;
revoke all on function private.enforce_active_seller_order_item_insert()
  from public, anon, authenticated;
revoke all on function private.enforce_active_seller_fulfillment()
  from public, anon, authenticated;
revoke all on function private.enforce_active_follow_target()
  from public, anon, authenticated;
revoke all on function private.enforce_conversation_membership()
  from public, anon, authenticated;
revoke all on function private.enforce_message_update_boundary()
  from public, anon, authenticated;
revoke all on function private.invalidate_changed_identity_evidence()
  from public, anon, authenticated;

commit;
