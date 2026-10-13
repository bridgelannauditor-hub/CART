-- Let a buyer sign up with an email already present in migrated profiles
-- without aborting the auth.users insert. The legacy profile is linked only
-- after Supabase confirms that the buyer owns the email address.

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_type text := coalesce(new.raw_user_meta_data ->> 'account_type', 'Customer');
  existing_profile public.profiles%rowtype;
  new_profile_id bigint;
  verification jsonb := new.raw_user_meta_data -> 'seller_verification';
  requested_phone text := nullif(trim(coalesce(
    new.raw_user_meta_data ->> 'phone',
    new.phone
  )), '');
begin
  if requested_type not in ('Customer', 'Seller') then
    requested_type := 'Customer';
  end if;

  select * into existing_profile
  from public.profiles
  where lower(email) = lower(coalesce(new.email, ''))
  limit 1;

  if existing_profile.id is not null then
    if existing_profile.auth_user_id is not null
       and existing_profile.auth_user_id <> new.id then
      raise exception 'This profile is already linked to another account.'
        using errcode = '23505';
    end if;

    -- Do not attach unconfirmed public sign-ups to migrated customer data.
    -- The update trigger below calls this function again after confirmation.
    if new.email_confirmed_at is null
       and coalesce(
         (new.raw_user_meta_data ->> 'migrated_from_firebase')::boolean,
         false
       ) is not true then
      return new;
    end if;

    update public.profiles
    set auth_user_id = new.id,
        email = coalesce(new.email, email),
        phone = coalesce(requested_phone, phone),
        updated_at = now()
    where id = existing_profile.id;

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
    requested_phone,
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
    ) on conflict (profile_id) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_email_confirmed on auth.users;
create trigger on_auth_user_email_confirmed
after update of email_confirmed_at on auth.users
for each row
when (old.email_confirmed_at is null and new.email_confirmed_at is not null)
execute function private.handle_new_auth_user();

