-- Phase 0, Stage 2: Buyer-only public signup and privileged-metadata containment.
--
-- This migration deliberately does not redefine private.is_seller(), change
-- seller RPC authorization, or populate seller_accounts. Seller enforcement is
-- reserved for a later reviewed stage.

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_profile public.profiles%rowtype;
  requested_first_name text := left(
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'first_name'), ''), 'Customer'),
    200
  );
  requested_last_name text := left(
    coalesce(new.raw_user_meta_data ->> 'last_name', ''),
    200
  );
  requested_phone text := left(
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'phone', new.phone)), ''),
    50
  );
  requested_avatar text := left(
    nullif(trim(new.raw_user_meta_data ->> 'avatar_url'), ''),
    2048
  );
begin
  -- Email is sourced only from the Auth row. Public metadata is intentionally
  -- ignored for roles, account type, shop state, approval, identity status,
  -- trust level, listing limits, and every other privileged field.
  -- Resolve an already-linked identity first. This prevents a confirmed Auth
  -- email change from trying to create a second profile for the same user.
  select * into existing_profile
  from public.profiles
  where auth_user_id = new.id
  limit 1;

  if existing_profile.id is null then
    select * into existing_profile
    from public.profiles
    where lower(email) = lower(coalesce(new.email, ''))
    limit 1;
  end if;

  if existing_profile.id is not null then
    if existing_profile.auth_user_id is not null
       and existing_profile.auth_user_id <> new.id then
      raise exception 'This profile is already linked to another account.'
        using errcode = '23505';
    end if;

    -- A public signup cannot claim a migrated profile using metadata. Linking
    -- occurs only after Supabase Auth confirms ownership of the email address.
    if new.email_confirmed_at is null then
      return new;
    end if;

    update public.profiles
    set auth_user_id = new.id,
        email = new.email,
        updated_at = now()
    where id = existing_profile.id
      and (auth_user_id is null or auth_user_id = new.id);

    if not found then
      raise exception 'This profile is already linked to another account.'
        using errcode = '23505';
    end if;

    return new;
  end if;

  insert into public.profiles (
    auth_user_id,
    first_name,
    last_name,
    email,
    phone,
    account_type,
    shop_name,
    profile_image,
    seller_verification,
    created_at
  ) values (
    new.id,
    requested_first_name,
    requested_last_name,
    coalesce(new.email, ''),
    requested_phone,
    'Customer',
    null,
    requested_avatar,
    null,
    coalesce(new.created_at, now())
  );

  return new;
end;
$$;

revoke all on function private.handle_new_auth_user()
  from public, anon, authenticated;

-- Preserve the existing creation and confirmation-linking behavior, but make
-- both triggers execute the Buyer-only implementation above.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_auth_user();

drop trigger if exists on_auth_user_email_confirmed on auth.users;
create trigger on_auth_user_email_confirmed
after update of email_confirmed_at on auth.users
for each row
when (old.email_confirmed_at is null and new.email_confirmed_at is not null)
execute function private.handle_new_auth_user();

-- These legacy secondary triggers trusted seller and verification metadata.
-- Remove them and replace their functions with defensive no-ops so recreating
-- a historical trigger cannot reapply untrusted metadata.
drop trigger if exists zz_capture_extended_seller_application on auth.users;
create or replace function private.capture_extended_seller_application()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  return new;
end;
$$;
revoke all on function private.capture_extended_seller_application()
  from public, anon, authenticated;

drop trigger if exists zz_sync_confirmed_school_email on auth.users;
create or replace function private.sync_confirmed_school_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  return new;
end;
$$;
revoke all on function private.sync_confirmed_school_email()
  from public, anon, authenticated;

-- Synchronize a stored profile email only from a confirmed Auth row. Clients
-- cannot invoke this trigger directly or supply the source email via profiles.
create or replace function private.sync_verified_auth_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email_confirmed_at is null or new.email is null then
    return new;
  end if;

  update public.profiles
  set email = new.email,
      updated_at = now()
  where auth_user_id = new.id
    and email is distinct from new.email;

  return new;
end;
$$;
revoke all on function private.sync_verified_auth_email()
  from public, anon, authenticated;

drop trigger if exists on_auth_user_verified_email_sync on auth.users;
create trigger on_auth_user_verified_email_sync
after update of email, email_confirmed_at on auth.users
for each row
when (
  new.email_confirmed_at is not null
  and (
    old.email is distinct from new.email
    or old.email_confirmed_at is distinct from new.email_confirmed_at
  )
)
execute function private.sync_verified_auth_email();

-- The owner-update RLS policy remains in place, but authenticated clients do
-- not receive column privileges for identity, role, approval, or trust fields.
revoke update (
  email,
  account_type,
  seller_verification,
  is_verified_seller,
  seller_tier,
  school_email_verified,
  verification_expiry,
  trust_score
) on public.profiles from authenticated;

-- Applicants may submit application facts for their own profile, but status,
-- level, limits, provider completion, and review results use database defaults
-- or trusted service-side processes only.
revoke insert, update, delete
on public.seller_verification_applications from authenticated;

grant insert (
  profile_id,
  seller_type,
  birth_date,
  address,
  identity_document_type,
  payout_method,
  payout_account_name,
  organization_name,
  business_registration_number,
  business_type,
  business_tax_id,
  business_address,
  representative_role
) on public.seller_verification_applications to authenticated;

