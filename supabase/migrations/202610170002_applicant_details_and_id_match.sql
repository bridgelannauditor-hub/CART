-- Seller application details + admin ID-match verification.
--
-- 1. The applicant's legal first/last name, birth date and complete address are
--    collected on the application so an administrator can compare them with the
--    uploaded ID.
-- 2. The payout method choice is removed; only the Payout Account Name remains.
-- 3. An administrator can mark identity "verified" only when ID photos were
--    actually submitted, and "verified" is the only path to approval.

alter table public.seller_verification_applications
  add column if not exists first_name text,
  add column if not exists last_name text;

alter table public.seller_verification_applications
  alter column payout_method drop not null;

-- ---------------------------------------------------------------------------
-- Submission (replaces the 202610150001 version).
-- ---------------------------------------------------------------------------
create or replace function public.submit_seller_application(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_profile_id bigint := private.current_profile_id();
  current_terms text := private.seller_onboarding_limits() ->> 'terms_version';
  existing public.seller_verification_applications%rowtype;
  applicant_type text := lower(trim(payload ->> 'sellerType'));
  applicant_tier integer;
  applicant_first_name text := nullif(trim(payload ->> 'firstName'), '');
  applicant_last_name text := nullif(trim(payload ->> 'lastName'), '');
  applicant_birth_date date := nullif(trim(payload ->> 'birthDate'), '')::date;
  applicant_address text := nullif(trim(payload ->> 'address'), '');
  applicant_document_type text := nullif(trim(payload ->> 'identityDocumentType'), '');
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
  if not exists (
    select 1 from auth.users u
    where u.id = (select auth.uid())
      and (u.email_confirmed_at is not null or u.phone_confirmed_at is not null)
  ) then
    raise exception 'Verify your email address or phone number before applying.' using errcode = '42501';
  end if;
  if coalesce(payload ->> 'acceptedTermsVersion', '') <> current_terms then
    raise exception 'The current Seller terms must be accepted.' using errcode = '22023';
  end if;
  if private.has_active_seller_authorization(caller_profile_id) then
    raise exception 'This account already has active seller authorization.' using errcode = '23514';
  end if;
  if applicant_type not in ('student', 'individual', 'business') then
    raise exception 'Invalid seller type.' using errcode = '22023';
  end if;

  if applicant_first_name is null or applicant_last_name is null
     or char_length(applicant_first_name) not between 2 and 60
     or char_length(applicant_last_name) not between 2 and 60
     or applicant_first_name !~ '^[[:alpha:]][[:alpha:] .''-]*$'
     or applicant_last_name !~ '^[[:alpha:]][[:alpha:] .''-]*$' then
    raise exception 'Enter your first and last name exactly as shown on your ID.' using errcode = '22023';
  end if;
  if applicant_birth_date is null or applicant_birth_date > current_date
     or applicant_birth_date < current_date - interval '120 years' then
    raise exception 'Enter a valid birth date.' using errcode = '22023';
  end if;
  if applicant_address is null or char_length(applicant_address) < 10
     or char_length(applicant_address) > 1000 then
    raise exception 'Enter your complete address.' using errcode = '22023';
  end if;
  if applicant_document_type not in (
       'student_id', 'national_id', 'passport', 'drivers_license',
       'postal_id', 'umid', 'prc_id'
     ) then
    raise exception 'Choose a valid ID type.' using errcode = '22023';
  end if;
  if applicant_payout_name is null or char_length(applicant_payout_name) not between 2 and 200 then
    raise exception 'Enter the payout account name.' using errcode = '22023';
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

  select * into existing
  from public.seller_verification_applications
  where profile_id = caller_profile_id
  for update;

  -- A rejected applicant may correct and resubmit (or appeal instead).
  if existing.status in ('approved', 'suspended', 'appealed') then
    raise exception 'This application cannot be resubmitted.' using errcode = '23514';
  end if;
  -- A failed identity check is reopened only by an admin after an appeal.
  if existing.identity_status = 'rejected' then
    raise exception 'Identity verification failed. Request a review instead of resubmitting.' using errcode = '23514';
  end if;

  insert into public.seller_verification_applications (
    profile_id, seller_type, first_name, last_name, birth_date, address,
    identity_document_type, payout_method, payout_account_name,
    organization_name, business_registration_number, status, level,
    listing_limit, submitted_at, reviewed_at, school_email,
    school_email_verified, credential_expiry, seller_tier, business_type,
    business_tax_id, business_address, representative_role,
    identity_capture_completed, face_capture_completed, terms_version,
    terms_accepted_at
  ) values (
    caller_profile_id, applicant_type, applicant_first_name, applicant_last_name,
    applicant_birth_date, applicant_address, applicant_document_type, null,
    applicant_payout_name, applicant_organization, applicant_registration,
    'under_review', 'registered', 5, now(), null, applicant_school_email,
    false, null, applicant_tier, applicant_business_type,
    applicant_business_tax_id, applicant_business_address,
    applicant_representative_role, false, false, current_terms, now()
  )
  on conflict (profile_id) do update set
    seller_type = excluded.seller_type,
    first_name = excluded.first_name,
    last_name = excluded.last_name,
    birth_date = excluded.birth_date,
    address = excluded.address,
    identity_document_type = excluded.identity_document_type,
    payout_method = null,
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
    terms_version = excluded.terms_version,
    terms_accepted_at = excluded.terms_accepted_at,
    revision = public.seller_verification_applications.revision + 1,
    -- Changed details must be matched against the ID again, so a previously
    -- verified identity is reopened for review when the details change.
    identity_status = case
      when public.seller_verification_applications.identity_status = 'verified'
       and (
         public.seller_verification_applications.first_name is distinct from excluded.first_name
         or public.seller_verification_applications.last_name is distinct from excluded.last_name
         or public.seller_verification_applications.birth_date is distinct from excluded.birth_date
         or public.seller_verification_applications.address is distinct from excluded.address
       ) then 'under_review'
      else public.seller_verification_applications.identity_status
    end,
    identity_verified_at = case
      when public.seller_verification_applications.identity_status = 'verified'
       and (
         public.seller_verification_applications.first_name is distinct from excluded.first_name
         or public.seller_verification_applications.last_name is distinct from excluded.last_name
         or public.seller_verification_applications.birth_date is distinct from excluded.birth_date
         or public.seller_verification_applications.address is distinct from excluded.address
       ) then null
      else public.seller_verification_applications.identity_verified_at
    end,
    shop_status = case
      when public.seller_verification_applications.shop_status in ('submitted', 'changes_requested') then 'draft'
      else public.seller_verification_applications.shop_status
    end;

  perform private.write_audit_log(
    'applicant',
    case when existing.profile_id is null then 'application_submitted' else 'application_resubmitted' end,
    caller_profile_id,
    jsonb_build_object('terms_version', current_terms, 'seller_type', applicant_type)
  );

  return jsonb_build_object('profile_id', caller_profile_id, 'status', 'under_review');
end;
$$;

revoke all on function public.submit_seller_application(jsonb) from public, anon, authenticated;
grant execute on function public.submit_seller_application(jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Admin queue: include what the admin must compare against the ID.
-- ---------------------------------------------------------------------------
drop function if exists public.admin_list_seller_applications(text);

create function public.admin_list_seller_applications(status_filter text default null)
returns table (
  profile_id bigint,
  applicant_name text,
  applicant_email text,
  seller_type text,
  status text,
  revision integer,
  identity_status text,
  identity_attempts integer,
  shop_status text,
  shop_name text,
  shop_description text,
  shop_category text,
  shop_city text,
  organization_name text,
  business_registration_number text,
  appeal_message text,
  submitted_at timestamptz,
  shop_submitted_at timestamptz,
  first_name text,
  last_name text,
  birth_date date,
  address text,
  identity_document_type text,
  payout_account_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select a.profile_id,
         trim(p.first_name || ' ' || p.last_name),
         p.email,
         a.seller_type,
         a.status,
         a.revision,
         a.identity_status,
         a.identity_attempts,
         a.shop_status,
         a.shop_name,
         a.shop_description,
         a.shop_category,
         a.shop_city,
         a.organization_name,
         a.business_registration_number,
         a.appeal_message,
         a.submitted_at,
         a.shop_submitted_at,
         a.first_name,
         a.last_name,
         a.birth_date,
         a.address,
         a.identity_document_type,
         a.payout_account_name
  from public.seller_verification_applications a
  join public.profiles p on p.id = a.profile_id
  where status_filter is null or a.status = status_filter
  order by coalesce(a.shop_submitted_at, a.submitted_at)
  limit 200;
end;
$$;

revoke all on function public.admin_list_seller_applications(text) from public, anon, authenticated;
grant execute on function public.admin_list_seller_applications(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Identity decision. "Verified" now requires submitted ID photos, so an
-- applicant can never be marked verified without something to compare.
-- ---------------------------------------------------------------------------
create or replace function public.admin_resolve_identity_review(
  target_profile_id bigint,
  verified boolean,
  reason_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  if target_profile_id = private.current_profile_id() then
    raise exception 'Administrators cannot review their own application.' using errcode = '42501';
  end if;

  if verified and not exists (
    select 1 from public.seller_verification_vault v
    where v.profile_id = target_profile_id
      and v.identity_document_path is not null
      and v.encrypted_metadata ->> 'selfiePath' is not null
  ) then
    raise exception 'No ID photos were submitted, so the details cannot be matched.' using errcode = '23514';
  end if;

  update public.seller_verification_applications
  set identity_status = case when verified then 'verified' else 'rejected' end,
      identity_reason_code = left(reason_code, 100),
      identity_verified_at = case when verified then now() else null end,
      identity_capture_completed = verified,
      face_capture_completed = verified,
      status = case when verified then status else 'rejected' end,
      review_reason_code = case when verified then review_reason_code else left(reason_code, 100) end,
      reviewed_by = (select auth.uid())
  where profile_id = target_profile_id and identity_status = 'under_review';
  if not found then
    raise exception 'No identity review is pending for this applicant.' using errcode = 'P0002';
  end if;

  perform private.write_audit_log('admin', 'identity_review_resolved', target_profile_id,
    jsonb_build_object('verified', verified, 'reason_code', reason_code));
end;
$$;

revoke all on function public.admin_resolve_identity_review(bigint, boolean, text)
  from public, anon, authenticated;
grant execute on function public.admin_resolve_identity_review(bigint, boolean, text) to authenticated;
