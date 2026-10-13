-- Link a newly created Supabase Auth identity to a migrated profile that owns
-- the same confirmed email address. New customers still receive a fresh
-- profile. This must run before provisioning Auth users for legacy profiles.

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_type text := coalesce(new.raw_user_meta_data ->> 'account_type', 'Customer');
  existing_profile_id bigint;
  new_profile_id bigint;
  verification jsonb := new.raw_user_meta_data -> 'seller_verification';
begin
  if requested_type not in ('Customer', 'Seller') then
    requested_type := 'Customer';
  end if;

  select id into existing_profile_id
  from public.profiles
  where lower(email) = lower(coalesce(new.email, ''))
  limit 1;

  if existing_profile_id is not null then
    -- Admin-provisioned migration users and verified OAuth identities arrive
    -- confirmed. Never attach an unconfirmed public sign-up to legacy data.
    if new.email_confirmed_at is null and
       coalesce((new.raw_user_meta_data ->> 'migrated_from_firebase')::boolean, false) is not true then
      raise exception 'Confirm this email through account recovery before linking the migrated profile.'
        using errcode = '42501';
    end if;

    update public.profiles
    set auth_user_id = new.id,
        email = coalesce(new.email, email),
        updated_at = now()
    where id = existing_profile_id
      and (auth_user_id is null or auth_user_id = new.id);

    if not found then
      raise exception 'This profile is already linked to another account.'
        using errcode = '23505';
    end if;
    return new;
  end if;

  insert into public.profiles (
    auth_user_id, first_name, last_name, email, phone, account_type, shop_name,
    profile_image, seller_verification, created_at
  ) values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'first_name'), ''), 'Customer'),
    coalesce(new.raw_user_meta_data ->> 'last_name', ''),
    coalesce(new.email, ''),
    new.phone,
    requested_type,
    nullif(trim(new.raw_user_meta_data ->> 'shop_name'), ''),
    new.raw_user_meta_data ->> 'avatar_url',
    case when requested_type = 'Seller' and verification is not null then
      jsonb_build_object(
        'sellerType', coalesce(verification ->> 'sellerType', 'individual'),
        'status', coalesce(verification ->> 'status', 'under_review'),
        'level', coalesce(verification ->> 'level', 'registered'),
        'listingLimit', coalesce((verification ->> 'listingLimit')::integer, 5),
        'submittedAt', coalesce(verification ->> 'submittedAt', now()::text)
      )
    else null end,
    coalesce(new.created_at, now())
  ) returning id into new_profile_id;

  if requested_type = 'Seller' and verification is not null then
    insert into public.seller_verification_applications (
      profile_id, seller_type, birth_date, address, identity_document_type,
      payout_method, payout_account_name, organization_name,
      business_registration_number, status, level, listing_limit, submitted_at
    ) values (
      new_profile_id,
      coalesce(verification ->> 'sellerType', 'individual'),
      (verification ->> 'birthDate')::date,
      verification ->> 'address',
      verification ->> 'identityDocumentType',
      verification ->> 'payoutMethod',
      verification ->> 'payoutAccountName',
      nullif(verification ->> 'organizationName', ''),
      nullif(verification ->> 'businessRegistrationNumber', ''),
      coalesce(verification ->> 'status', 'under_review'),
      coalesce(verification ->> 'level', 'registered'),
      coalesce((verification ->> 'listingLimit')::integer, 5),
      coalesce((verification ->> 'submittedAt')::timestamptz, now())
    );
  end if;

  return new;
end;
$$;
