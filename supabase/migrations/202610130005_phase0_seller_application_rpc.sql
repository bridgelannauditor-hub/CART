-- Phase 0 remediation: seller applications are submitted after Buyer signup by
-- an authenticated caller. Approval and verification fields are server-owned.

create or replace function public.submit_seller_application(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_profile_id bigint := private.current_profile_id();
  application_status text;
  applicant_type text := lower(trim(payload ->> 'sellerType'));
  applicant_tier integer;
  applicant_birth_date date := nullif(trim(payload ->> 'birthDate'), '')::date;
  applicant_address text := nullif(trim(payload ->> 'address'), '');
  applicant_document_type text := nullif(trim(payload ->> 'identityDocumentType'), '');
  applicant_payout_method text := nullif(trim(payload ->> 'payoutMethod'), '');
  applicant_payout_name text := nullif(trim(payload ->> 'payoutAccountName'), '');
  applicant_organization text := nullif(trim(payload ->> 'organizationName'), '');
  applicant_registration text := nullif(trim(payload ->> 'businessRegistrationNumber'), '');
  applicant_school_email text := nullif(lower(trim(payload ->> 'schoolEmail')), '');
  applicant_business_type text := nullif(trim(payload ->> 'businessType'), '');
  applicant_business_tax_id text := nullif(trim(payload ->> 'businessTaxId'), '');
  applicant_business_address text := nullif(trim(payload ->> 'businessAddress'), '');
  applicant_representative_role text := nullif(trim(payload ->> 'representativeRole'), '');
begin
  if caller_profile_id is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;
  if private.has_active_seller_authorization(caller_profile_id) then
    raise exception 'This account already has active seller authorization.' using errcode = '23514';
  end if;
  if applicant_type not in ('student', 'individual', 'business') then
    raise exception 'Invalid seller type.' using errcode = '22023';
  end if;
  if applicant_birth_date is null or applicant_birth_date > current_date
     or applicant_address is null or char_length(applicant_address) > 1000
     or applicant_document_type not in (
       'student_id', 'national_id', 'passport', 'drivers_license',
       'postal_id', 'umid', 'prc_id'
     )
     or applicant_payout_method not in ('gcash', 'maya', 'bank')
     or applicant_payout_name is null or char_length(applicant_payout_name) > 200 then
    raise exception 'Required application details are invalid.' using errcode = '22023';
  end if;
  if applicant_type = 'student' and (
    applicant_school_email is null
    or not private.is_ph_school_email(applicant_school_email)
  ) then
    raise exception 'A school email is required for student applications.' using errcode = '22023';
  end if;
  if applicant_type = 'business'
     and (
       applicant_organization is null or applicant_registration is null
       or applicant_business_type is null or applicant_business_tax_id is null
       or applicant_business_address is null
       or applicant_representative_role is null
     ) then
    raise exception 'Business organization and registration details are required.' using errcode = '22023';
  end if;

  applicant_tier := case applicant_type
    when 'student' then 1
    when 'individual' then 2
    else 3
  end;

  select status into application_status
  from public.seller_verification_applications
  where profile_id = caller_profile_id
  for update;

  if application_status in ('approved', 'suspended') then
    raise exception 'This application cannot be resubmitted.' using errcode = '23514';
  end if;

  insert into public.seller_verification_applications (
    profile_id, seller_type, birth_date, address, identity_document_type,
    payout_method, payout_account_name, organization_name,
    business_registration_number, status, level, listing_limit, submitted_at,
    reviewed_at, school_email, school_email_verified, credential_expiry,
    seller_tier, business_type, business_tax_id, business_address,
    representative_role, identity_capture_completed, face_capture_completed
  ) values (
    caller_profile_id, applicant_type, applicant_birth_date, applicant_address,
    applicant_document_type, applicant_payout_method, applicant_payout_name,
    applicant_organization, applicant_registration, 'under_review',
    'registered', 5, now(), null, applicant_school_email, false, null,
    applicant_tier, applicant_business_type, applicant_business_tax_id,
    applicant_business_address, applicant_representative_role, false, false
  )
  on conflict (profile_id) do update set
    seller_type = excluded.seller_type,
    birth_date = excluded.birth_date,
    address = excluded.address,
    identity_document_type = excluded.identity_document_type,
    payout_method = excluded.payout_method,
    payout_account_name = excluded.payout_account_name,
    organization_name = excluded.organization_name,
    business_registration_number = excluded.business_registration_number,
    status = 'under_review',
    level = 'registered',
    listing_limit = 5,
    submitted_at = now(),
    reviewed_at = null,
    school_email = excluded.school_email,
    school_email_verified = false,
    credential_expiry = null,
    seller_tier = excluded.seller_tier,
    business_type = excluded.business_type,
    business_tax_id = excluded.business_tax_id,
    business_address = excluded.business_address,
    representative_role = excluded.representative_role,
    identity_capture_completed = false,
    face_capture_completed = false;

  return jsonb_build_object(
    'profile_id', caller_profile_id,
    'status', 'under_review'
  );
end;
$$;

revoke all on function public.submit_seller_application(jsonb)
  from public, anon, authenticated;
grant execute on function public.submit_seller_application(jsonb)
  to authenticated, service_role;

-- Submission must go through the caller-bound RPC, not direct table writes.
revoke insert (
  profile_id, seller_type, birth_date, address, identity_document_type,
  payout_method, payout_account_name, organization_name,
  business_registration_number, business_type, business_tax_id,
  business_address, representative_role
) on public.seller_verification_applications from authenticated;

