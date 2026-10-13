-- Preserve the extended seller-onboarding answers collected by the app.
-- Raw ID/face images must be sent to private verification storage by a
-- dedicated provider integration; this table records only completion state.

alter table public.seller_verification_applications
  add column if not exists business_type text,
  add column if not exists business_tax_id text,
  add column if not exists business_address text,
  add column if not exists representative_role text,
  add column if not exists identity_capture_completed boolean not null default false,
  add column if not exists face_capture_completed boolean not null default false;

create or replace function private.capture_extended_seller_application()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_key bigint;
  verification jsonb := new.raw_user_meta_data -> 'seller_verification';
begin
  select id into profile_key
  from public.profiles
  where auth_user_id = new.id;

  update public.profiles
  set phone = nullif(trim(new.raw_user_meta_data ->> 'phone'), '')
  where id = profile_key;

  if coalesce(new.raw_user_meta_data ->> 'account_type', 'Customer') <> 'Seller'
     or verification is null then
    return new;
  end if;

  update public.seller_verification_applications
  set business_type = nullif(verification ->> 'businessType', ''),
      business_tax_id = nullif(verification ->> 'businessTaxId', ''),
      business_address = nullif(verification ->> 'businessAddress', ''),
      representative_role = nullif(verification ->> 'representativeRole', ''),
      identity_capture_completed =
        coalesce((verification ->> 'identityCaptureCompleted')::boolean, false),
      face_capture_completed =
        coalesce((verification ->> 'faceCaptureCompleted')::boolean, false)
  where profile_id = profile_key;

  return new;
end;
$$;

drop trigger if exists zz_capture_extended_seller_application on auth.users;
create trigger zz_capture_extended_seller_application
after insert on auth.users
for each row execute function private.capture_extended_seller_application();
