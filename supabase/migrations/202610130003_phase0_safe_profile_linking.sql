-- Phase 0 remediation: public Auth linking may claim Buyer profiles only.
-- Legacy Seller recovery remains a trusted service-side operation.

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
  requested_last_name text := left(coalesce(new.raw_user_meta_data ->> 'last_name', ''), 200);
  requested_phone text := left(
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'phone', new.phone)), ''),
    50
  );
  requested_avatar text := left(nullif(trim(new.raw_user_meta_data ->> 'avatar_url'), ''), 2048);
begin
  if new.email is null or trim(new.email) = '' then
    raise exception 'Email registration is required.' using errcode = '22023';
  end if;

  -- An identity already linked to a profile always wins over email matching.
  select * into existing_profile
  from public.profiles
  where auth_user_id = new.id
  limit 1
  for update;

  if existing_profile.id is not null then
    if new.email_confirmed_at is not null then
      update public.profiles
      set email = new.email,
          updated_at = now()
      where id = existing_profile.id and auth_user_id = new.id;
    end if;
    return new;
  end if;

  select * into existing_profile
  from public.profiles
  where lower(email) = lower(new.email)
  limit 1
  for update;

  if existing_profile.id is not null then
    if existing_profile.auth_user_id is not null
       and existing_profile.auth_user_id <> new.id then
      raise exception 'This profile is already linked to another account.'
        using errcode = '23505';
    end if;

    -- Public Auth events may not claim legacy Seller profiles. A trusted
    -- service-role recovery/provisioning process must link those records.
    if existing_profile.account_type <> 'Customer' then
      return new;
    end if;

    if new.email_confirmed_at is null then
      return new;
    end if;

    update public.profiles
    set auth_user_id = new.id,
        email = new.email,
        updated_at = now()
    where id = existing_profile.id
      and account_type = 'Customer'
      and (auth_user_id is null or auth_user_id = new.id);

    if not found then
      raise exception 'This profile is already linked to another account.'
        using errcode = '23505';
    end if;

    return new;
  end if;

  insert into public.profiles (
    auth_user_id, first_name, last_name, email, phone, account_type,
    shop_name, profile_image, seller_verification, created_at
  ) values (
    new.id, requested_first_name, requested_last_name, new.email,
    requested_phone, 'Customer', null, requested_avatar, null,
    coalesce(new.created_at, now())
  );

  return new;
end;
$$;

revoke all on function private.handle_new_auth_user()
  from public, anon, authenticated;

