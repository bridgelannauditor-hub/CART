-- Seller onboarding: terms, identity-verification sessions, shop setup, admin
-- approval, and an append-only audit log.
--
-- Records and their purpose:
--   profiles                          general account and customer information
--   seller_verification_applications  application, shop draft, review status
--   verification_sessions             provider reference, session status, timestamps
--   seller_accounts                   approved seller status (Phase 0 table)
--   audit_logs                        verification and approval actions
--   admin_users                       admins provisioned by a trusted process
--
-- Identity documents and selfies never pass through these tables. The
-- verification provider holds the evidence; Cart stores only the provider
-- reference and the outcome.
--
-- This migration activates no existing account. Seller permissions are granted
-- only by public.admin_review_seller_application.

-- ---------------------------------------------------------------------------
-- Admins: provisioned by a service-role process, never through public signup.
-- ---------------------------------------------------------------------------

create table public.admin_users (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  granted_by text not null check (char_length(trim(granted_by)) between 1 and 200),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint admin_revocation_order check (revoked_at is null or revoked_at >= granted_at)
);

comment on table public.admin_users is
  'Marketplace administrators. Written only by trusted service-role provisioning; never from signup metadata or profiles.';

alter table public.admin_users enable row level security;
revoke all on table public.admin_users from public, anon, authenticated;
grant all on table public.admin_users to service_role;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admin_users a
    where a.auth_user_id = (select auth.uid())
      and a.revoked_at is null
  );
$$;

revoke all on function private.is_admin() from public, anon, authenticated;
grant execute on function private.is_admin() to authenticated, service_role;

-- Lets the client decide whether to show the admin screen. Every admin RPC
-- repeats the check, so this answer grants nothing by itself.
create or replace function public.am_i_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_admin();
$$;

revoke all on function public.am_i_admin() from public, anon, authenticated;
grant execute on function public.am_i_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- Audit log: append-only.
-- ---------------------------------------------------------------------------

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_auth_user_id uuid references auth.users(id) on delete set null,
  actor_kind text not null check (actor_kind in ('applicant', 'admin', 'provider', 'service')),
  action text not null check (char_length(action) between 1 and 100),
  target_profile_id bigint references public.profiles(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index audit_logs_target_idx on public.audit_logs (target_profile_id, created_at desc);

create or replace function private.reject_audit_log_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Audit log entries are append-only.' using errcode = '42501';
end;
$$;

create trigger audit_logs_append_only
before update or delete on public.audit_logs
for each row execute function private.reject_audit_log_change();

alter table public.audit_logs enable row level security;
revoke all on table public.audit_logs from public, anon, authenticated;
grant select, insert on table public.audit_logs to service_role;
grant select on table public.audit_logs to authenticated;

create policy audit_logs_admin_read on public.audit_logs
for select to authenticated
using ((select private.is_admin()));

create or replace function private.write_audit_log(
  actor_kind text,
  action text,
  target_profile_id bigint,
  details jsonb default '{}'::jsonb
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_logs (actor_auth_user_id, actor_kind, action, target_profile_id, details)
  values ((select auth.uid()), actor_kind, action, target_profile_id, coalesce(details, '{}'::jsonb));
$$;

revoke all on function private.write_audit_log(text, text, bigint, jsonb)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Application: terms, identity outcome, shop draft, review, appeal.
-- ---------------------------------------------------------------------------

alter table public.seller_verification_applications
  drop constraint if exists seller_verification_applications_status_check;
alter table public.seller_verification_applications
  add constraint seller_verification_applications_status_check
  check (status in ('under_review', 'approved', 'rejected', 'suspended', 'appealed'));

alter table public.seller_verification_applications
  add column if not exists revision integer not null default 1 check (revision >= 1),
  add column if not exists terms_version text,
  add column if not exists terms_accepted_at timestamptz,
  add column if not exists identity_status text not null default 'not_started'
    check (identity_status in ('not_started', 'pending', 'verified', 'needs_retry', 'under_review', 'rejected')),
  add column if not exists identity_attempts integer not null default 0 check (identity_attempts >= 0),
  add column if not exists identity_reason_code text,
  add column if not exists identity_verified_at timestamptz,
  add column if not exists shop_status text not null default 'not_started'
    check (shop_status in ('not_started', 'draft', 'submitted', 'changes_requested', 'approved', 'rejected')),
  add column if not exists shop_name text check (shop_name is null or char_length(shop_name) between 3 and 60),
  add column if not exists shop_description text check (shop_description is null or char_length(shop_description) <= 1000),
  add column if not exists shop_category text check (shop_category is null or char_length(shop_category) <= 100),
  add column if not exists shop_city text check (shop_city is null or char_length(shop_city) <= 100),
  add column if not exists shop_submitted_at timestamptz,
  add column if not exists review_reason_code text,
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists appeal_message text check (appeal_message is null or char_length(appeal_message) <= 1000),
  add column if not exists appealed_at timestamptz,
  add column if not exists appeal_count integer not null default 0 check (appeal_count >= 0);

create unique index if not exists seller_applications_shop_name_idx
  on public.seller_verification_applications (lower(shop_name))
  where shop_name is not null and shop_status <> 'rejected';

-- Every new column is server-owned. Clients change them only through RPCs.
revoke insert, update on public.seller_verification_applications from authenticated;

-- ---------------------------------------------------------------------------
-- Verification sessions: one row per provider session.
-- ---------------------------------------------------------------------------

create table public.verification_sessions (
  id uuid primary key default gen_random_uuid(),
  profile_id bigint not null references public.profiles(id) on delete cascade,
  application_revision integer not null,
  provider text not null check (char_length(provider) between 1 and 50),
  provider_session_id text unique,
  status text not null default 'created'
    check (status in ('created', 'pending', 'verified', 'needs_retry', 'under_review', 'rejected', 'expired', 'failed')),
  reason_code text,
  checks jsonb not null default '{}'::jsonb,
  last_event_id text,
  expires_at timestamptz,
  result_received_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.verification_sessions is
  'Identity-verification provider references and outcomes. Raw ID and selfie images are held by the provider, not here.';
comment on column public.verification_sessions.checks is
  'Pass/fail flags only, for example {"document":true,"liveness":true,"face_match":true}. Never images or extracted ID data.';

create index verification_sessions_profile_idx
  on public.verification_sessions (profile_id, created_at desc);

create trigger verification_sessions_set_updated_at
before update on public.verification_sessions
for each row execute function private.set_updated_at();

alter table public.verification_sessions enable row level security;
revoke all on table public.verification_sessions from public, anon, authenticated;
grant all on table public.verification_sessions to service_role;
grant select (id, profile_id, status, reason_code, expires_at, result_received_at, created_at)
  on public.verification_sessions to authenticated;

create policy verification_sessions_read_own on public.verification_sessions
for select to authenticated
using (profile_id = (select private.current_profile_id()));

-- Tunables kept in one place so tests and docs can reference them.
create or replace function private.seller_onboarding_limits()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'max_identity_attempts', 3,
    'max_sessions_per_day', 5,
    'max_appeals', 2,
    'terms_version', '2026-10'
  );
$$;

revoke all on function private.seller_onboarding_limits() from public, anon;
grant execute on function private.seller_onboarding_limits() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Step 2: application submission now requires accepting the current terms.
-- Replaces the Phase 0 version; validation rules are unchanged.
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
    profile_id, seller_type, birth_date, address, identity_document_type,
    payout_method, payout_account_name, organization_name,
    business_registration_number, status, level, listing_limit, submitted_at,
    reviewed_at, school_email, school_email_verified, credential_expiry,
    seller_tier, business_type, business_tax_id, business_address,
    representative_role, identity_capture_completed, face_capture_completed,
    terms_version, terms_accepted_at
  ) values (
    caller_profile_id, applicant_type, applicant_birth_date, applicant_address,
    applicant_document_type, applicant_payout_method, applicant_payout_name,
    applicant_organization, applicant_registration, 'under_review',
    'registered', 5, now(), null, applicant_school_email, false, null,
    applicant_tier, applicant_business_type, applicant_business_tax_id,
    applicant_business_address, applicant_representative_role, false, false,
    current_terms, now()
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
    terms_version = excluded.terms_version,
    terms_accepted_at = excluded.terms_accepted_at,
    revision = public.seller_verification_applications.revision + 1,
    -- Changed details need a fresh shop review; identity results are kept.
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
-- Step 3: identity verification sessions.
--
-- Flutter -> Edge Function `create-verification-session` (user JWT)
--   -> public.begin_identity_verification()          as the user
--   -> provider API                                    server-to-server
--   -> public.service_attach_verification_session()  as service_role
-- Provider webhook -> Edge Function `verification-webhook` (signature checked)
--   -> public.service_record_verification_result()   as service_role
-- ---------------------------------------------------------------------------

create or replace function public.begin_identity_verification(provider_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_profile_id bigint := private.current_profile_id();
  limits jsonb := private.seller_onboarding_limits();
  application public.seller_verification_applications%rowtype;
  new_session_id uuid;
begin
  if caller_profile_id is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  select * into application
  from public.seller_verification_applications
  where profile_id = caller_profile_id
  for update;

  if not found or application.terms_accepted_at is null then
    raise exception 'Submit the Seller application and accept the terms first.' using errcode = '23514';
  end if;
  if application.status not in ('under_review') then
    raise exception 'Identity verification is not available for this application.' using errcode = '23514';
  end if;
  if application.identity_status not in ('not_started', 'pending', 'needs_retry') then
    raise exception 'Identity verification is not available in the current state.' using errcode = '23514';
  end if;
  if application.identity_attempts >= (limits ->> 'max_identity_attempts')::integer then
    raise exception 'No verification attempts remain. The application is waiting for manual review.' using errcode = '23514';
  end if;
  if (
    select count(*) from public.verification_sessions s
    where s.profile_id = caller_profile_id and s.created_at > now() - interval '1 day'
  ) >= (limits ->> 'max_sessions_per_day')::integer then
    raise exception 'Too many verification sessions today. Try again tomorrow.' using errcode = '54000';
  end if;

  -- Only one live session per applicant.
  update public.verification_sessions
  set status = 'expired'
  where profile_id = caller_profile_id and status in ('created', 'pending');

  insert into public.verification_sessions (profile_id, application_revision, provider)
  values (caller_profile_id, application.revision, provider_name)
  returning id into new_session_id;

  update public.seller_verification_applications
  set identity_status = 'pending'
  where profile_id = caller_profile_id;

  perform private.write_audit_log('applicant', 'identity_session_started', caller_profile_id,
    jsonb_build_object('session_id', new_session_id, 'provider', provider_name));

  return new_session_id;
end;
$$;

revoke all on function public.begin_identity_verification(text) from public, anon, authenticated;
grant execute on function public.begin_identity_verification(text) to authenticated;

create or replace function public.service_attach_verification_session(
  session_id uuid,
  provider_session_ref text,
  session_expires_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.verification_sessions
  set provider_session_id = provider_session_ref,
      expires_at = session_expires_at,
      status = 'pending'
  where id = session_id and status = 'created';
  if not found then
    raise exception 'Verification session is not awaiting a provider reference.' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.service_attach_verification_session(uuid, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.service_attach_verification_session(uuid, text, timestamptz)
  to service_role;

create or replace function public.service_fail_verification_session(session_id uuid, reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile bigint;
begin
  update public.verification_sessions
  set status = 'failed', reason_code = left(reason, 100)
  where id = session_id and status = 'created'
  returning profile_id into target_profile;

  -- A provider/technical failure is not the applicant's fault: no attempt is used.
  update public.seller_verification_applications
  set identity_status = case when identity_attempts > 0 then 'needs_retry' else 'not_started' end
  where profile_id = target_profile and identity_status = 'pending';
end;
$$;

revoke all on function public.service_fail_verification_session(uuid, text)
  from public, anon, authenticated;
grant execute on function public.service_fail_verification_session(uuid, text) to service_role;

-- Called only after the Edge Function has verified the provider's signature.
-- Idempotent per provider event id.
create or replace function public.service_record_verification_result(
  provider_session_ref text,
  event_id text,
  outcome text,
  reason text default null,
  check_results jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  vsession public.verification_sessions%rowtype;
  application public.seller_verification_applications%rowtype;
  max_attempts integer := (private.seller_onboarding_limits() ->> 'max_identity_attempts')::integer;
  attempts integer;
  new_identity_status text;
  safe_checks jsonb;
begin
  if outcome not in ('verified', 'needs_retry', 'under_review', 'rejected') then
    raise exception 'Unknown verification outcome.' using errcode = '22023';
  end if;

  select * into vsession
  from public.verification_sessions
  where provider_session_id = provider_session_ref
  for update;
  if not found then
    raise exception 'Unknown verification session.' using errcode = 'P0002';
  end if;
  if vsession.last_event_id is not distinct from event_id then
    return jsonb_build_object('status', vsession.status, 'duplicate', true);
  end if;
  if vsession.status not in ('pending', 'under_review') then
    -- Late events for expired or superseded sessions are recorded but ignored.
    perform private.write_audit_log('provider', 'identity_result_ignored', vsession.profile_id,
      jsonb_build_object('session_id', vsession.id, 'session_status', vsession.status, 'outcome', outcome));
    return jsonb_build_object('status', vsession.status, 'ignored', true);
  end if;

  select * into application
  from public.seller_verification_applications
  where profile_id = vsession.profile_id
  for update;

  -- Keep only boolean flags from the provider payload.
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into safe_checks
  from jsonb_each(coalesce(check_results, '{}'::jsonb))
  where key in ('document', 'liveness', 'face_match', 'personal_details')
    and jsonb_typeof(value) = 'boolean';

  attempts := application.identity_attempts + case when outcome = 'needs_retry' then 1 else 0 end;
  new_identity_status := case
    when outcome = 'needs_retry' and attempts >= max_attempts then 'under_review'
    else outcome
  end;

  update public.verification_sessions
  set status = outcome,
      reason_code = left(reason, 100),
      checks = safe_checks,
      last_event_id = event_id,
      result_received_at = now()
  where id = vsession.id;

  -- A result for an older application revision does not change the application.
  if application.revision = vsession.application_revision
     and application.identity_status in ('pending', 'under_review') then
    update public.seller_verification_applications
    set identity_status = new_identity_status,
        identity_attempts = attempts,
        identity_reason_code = left(reason, 100),
        identity_verified_at = case when new_identity_status = 'verified' then now() else null end,
        identity_capture_completed = new_identity_status = 'verified',
        face_capture_completed = new_identity_status = 'verified',
        -- A rejection closes the application so the applicant can appeal.
        status = case when new_identity_status = 'rejected' then 'rejected' else status end,
        review_reason_code = case
          when new_identity_status = 'rejected' then left(reason, 100)
          else review_reason_code
        end
    where profile_id = vsession.profile_id;
  end if;

  perform private.write_audit_log('provider', 'identity_result_recorded', vsession.profile_id,
    jsonb_build_object('session_id', vsession.id, 'outcome', outcome,
      'identity_status', new_identity_status, 'attempts', attempts));

  return jsonb_build_object('status', new_identity_status, 'attempts', attempts);
end;
$$;

revoke all on function public.service_record_verification_result(text, text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.service_record_verification_result(text, text, text, text, jsonb)
  to service_role;

-- ---------------------------------------------------------------------------
-- Step 5: shop setup, allowed only after identity verification succeeds.
-- ---------------------------------------------------------------------------

create or replace function public.save_shop_draft(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_profile_id bigint := private.current_profile_id();
  application public.seller_verification_applications%rowtype;
  draft_name text := nullif(trim(payload ->> 'shopName'), '');
  draft_description text := nullif(trim(payload ->> 'shopDescription'), '');
  draft_category text := nullif(trim(payload ->> 'shopCategory'), '');
  draft_city text := nullif(trim(payload ->> 'shopCity'), '');
  submit_now boolean := coalesce((payload ->> 'submit')::boolean, false);
begin
  if caller_profile_id is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  select * into application
  from public.seller_verification_applications
  where profile_id = caller_profile_id
  for update;

  if not found or application.identity_status <> 'verified' then
    raise exception 'Complete identity verification before setting up a shop.' using errcode = '42501';
  end if;
  if application.status <> 'under_review'
     or application.shop_status not in ('not_started', 'draft', 'changes_requested') then
    raise exception 'The shop cannot be edited in the current state.' using errcode = '23514';
  end if;
  if draft_name is null or char_length(draft_name) not between 3 and 60
     or draft_name !~ '^[[:alnum:]][[:alnum:] &''.,-]*$' then
    raise exception 'Shop name must be 3-60 letters, numbers, or simple punctuation.' using errcode = '22023';
  end if;
  if char_length(coalesce(draft_description, '')) > 1000
     or char_length(coalesce(draft_category, '')) > 100
     or char_length(coalesce(draft_city, '')) > 100 then
    raise exception 'Shop details are too long.' using errcode = '22023';
  end if;
  if submit_now and (draft_description is null or draft_category is null or draft_city is null) then
    raise exception 'Description, category, and city are required to submit the shop.' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.profiles p
    where lower(p.shop_name) = lower(draft_name) and p.id <> caller_profile_id
  ) then
    raise exception 'That shop name is already taken.' using errcode = '23505';
  end if;

  update public.seller_verification_applications
  set shop_name = draft_name,
      shop_description = draft_description,
      shop_category = draft_category,
      shop_city = draft_city,
      shop_status = case when submit_now then 'submitted' else 'draft' end,
      shop_submitted_at = case when submit_now then now() else shop_submitted_at end
  where profile_id = caller_profile_id;

  if submit_now then
    perform private.write_audit_log('applicant', 'shop_submitted', caller_profile_id,
      jsonb_build_object('revision', application.revision, 'shop_name', draft_name));
  end if;

  return jsonb_build_object('shop_status', case when submit_now then 'submitted' else 'draft' end);
end;
$$;

revoke all on function public.save_shop_draft(jsonb) from public, anon, authenticated;
grant execute on function public.save_shop_draft(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Appeal: a rejected applicant may ask for another review a limited number of
-- times. The case returns to admin review; nothing is approved automatically.
-- ---------------------------------------------------------------------------

create or replace function public.appeal_seller_application(message text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_profile_id bigint := private.current_profile_id();
  application public.seller_verification_applications%rowtype;
begin
  if caller_profile_id is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(message, ''))) not between 10 and 1000 then
    raise exception 'Explain the appeal in 10-1000 characters.' using errcode = '22023';
  end if;

  select * into application
  from public.seller_verification_applications
  where profile_id = caller_profile_id
  for update;

  if not found or application.status <> 'rejected' then
    raise exception 'Only a rejected application can be appealed.' using errcode = '23514';
  end if;
  if application.appeal_count >= (private.seller_onboarding_limits() ->> 'max_appeals')::integer then
    raise exception 'No appeals remain for this application.' using errcode = '23514';
  end if;

  update public.seller_verification_applications
  set status = 'appealed',
      appeal_message = trim(message),
      appealed_at = now(),
      appeal_count = appeal_count + 1
  where profile_id = caller_profile_id;

  perform private.write_audit_log('applicant', 'application_appealed', caller_profile_id,
    jsonb_build_object('appeal_count', application.appeal_count + 1));

  return jsonb_build_object('status', 'appealed');
end;
$$;

revoke all on function public.appeal_seller_application(text) from public, anon, authenticated;
grant execute on function public.appeal_seller_application(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Applicant status for the Flutter onboarding screen.
-- ---------------------------------------------------------------------------

create or replace function public.get_my_seller_onboarding()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_profile_id bigint := private.current_profile_id();
  limits jsonb := private.seller_onboarding_limits();
  application public.seller_verification_applications%rowtype;
  account_status text;
  email_verified boolean;
begin
  if caller_profile_id is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  select (u.email_confirmed_at is not null or u.phone_confirmed_at is not null)
  into email_verified
  from auth.users u where u.id = (select auth.uid());

  select sa.status into account_status
  from public.seller_accounts sa where sa.profile_id = caller_profile_id;

  select * into application
  from public.seller_verification_applications
  where profile_id = caller_profile_id;

  return jsonb_build_object(
    'accountVerified', coalesce(email_verified, false),
    'currentTermsVersion', limits ->> 'terms_version',
    'maxIdentityAttempts', (limits ->> 'max_identity_attempts')::integer,
    'maxAppeals', (limits ->> 'max_appeals')::integer,
    'sellerAccountStatus', account_status,
    'application', case when application.profile_id is null then null else jsonb_build_object(
      'status', application.status,
      'revision', application.revision,
      'sellerType', application.seller_type,
      'termsVersion', application.terms_version,
      'identityStatus', application.identity_status,
      'identityAttempts', application.identity_attempts,
      'identityReasonCode', application.identity_reason_code,
      'shopStatus', application.shop_status,
      'shopName', application.shop_name,
      'shopDescription', application.shop_description,
      'shopCategory', application.shop_category,
      'shopCity', application.shop_city,
      'reviewReasonCode', application.review_reason_code,
      'appealCount', application.appeal_count,
      'submittedAt', application.submitted_at,
      'reviewedAt', application.reviewed_at
    ) end
  );
end;
$$;

revoke all on function public.get_my_seller_onboarding() from public, anon, authenticated;
grant execute on function public.get_my_seller_onboarding() to authenticated;

-- ---------------------------------------------------------------------------
-- Step 6 and admin tools. Every function re-checks private.is_admin().
-- ---------------------------------------------------------------------------

create or replace function private.require_admin()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Administrator access required.' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.require_admin() from public, anon, authenticated;

create or replace function public.admin_list_seller_applications(status_filter text default null)
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
  shop_submitted_at timestamptz
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
         a.shop_submitted_at
  from public.seller_verification_applications a
  join public.profiles p on p.id = a.profile_id
  where status_filter is null or a.status = status_filter
  order by coalesce(a.shop_submitted_at, a.submitted_at)
  limit 200;
end;
$$;

revoke all on function public.admin_list_seller_applications(text) from public, anon, authenticated;
grant execute on function public.admin_list_seller_applications(text) to authenticated;

-- Resolves cases the provider could not decide (identity_status = under_review).
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

-- Final approval. Approval is tied to the reviewed application revision so a
-- change made after the admin looked at it cannot be approved by accident.
create or replace function public.admin_review_seller_application(
  target_profile_id bigint,
  expected_revision integer,
  decision text,
  reason_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  application public.seller_verification_applications%rowtype;
begin
  perform private.require_admin();
  if decision not in ('approve', 'reject', 'request_changes') then
    raise exception 'Unknown review decision.' using errcode = '22023';
  end if;
  if decision <> 'approve' and nullif(trim(reason_code), '') is null then
    raise exception 'A reason code is required.' using errcode = '22023';
  end if;
  if target_profile_id = private.current_profile_id() then
    raise exception 'Administrators cannot review their own application.' using errcode = '42501';
  end if;

  select * into application
  from public.seller_verification_applications
  where profile_id = target_profile_id
  for update;
  if not found then
    raise exception 'Application not found.' using errcode = 'P0002';
  end if;
  if application.revision <> expected_revision then
    raise exception 'The application changed since it was opened. Reload and review again.' using errcode = '40001';
  end if;
  if application.status not in ('under_review', 'appealed') then
    raise exception 'This application is not awaiting review.' using errcode = '23514';
  end if;

  if decision = 'approve' then
    if application.terms_accepted_at is null
       or application.identity_status <> 'verified'
       or application.shop_status <> 'submitted' then
      raise exception 'Approval requires accepted terms, verified identity, and a submitted shop.' using errcode = '23514';
    end if;
    if application.seller_type = 'student' and not application.school_email_verified then
      raise exception 'Student approval requires a verified school email.' using errcode = '23514';
    end if;

    update public.seller_verification_applications
    set status = 'approved', shop_status = 'approved', reviewed_at = now(),
        reviewed_by = (select auth.uid()), review_reason_code = null
    where profile_id = target_profile_id;

    update public.profiles
    set account_type = 'Seller',
        shop_name = application.shop_name,
        is_verified_seller = true,
        seller_tier = application.seller_tier
    where id = target_profile_id;

    insert into public.seller_accounts (profile_id, status, approved_by, approved_at, status_reason)
    values (target_profile_id, 'active', (select auth.uid()), now(), 'application revision ' || application.revision)
    on conflict (profile_id) do update set
      status = 'active',
      approved_by = excluded.approved_by,
      approved_at = excluded.approved_at,
      status_reason = excluded.status_reason;
  elsif decision = 'request_changes' then
    update public.seller_verification_applications
    set status = 'under_review',
        shop_status = case when shop_status in ('submitted', 'draft') then 'changes_requested' else shop_status end,
        -- After an appeal, the admin may grant a fresh set of identity attempts.
        identity_status = case
          when identity_status in ('rejected', 'under_review') then 'needs_retry'
          else identity_status
        end,
        identity_attempts = case
          when identity_status in ('rejected', 'under_review') then 0
          else identity_attempts
        end,
        review_reason_code = left(reason_code, 100),
        reviewed_by = (select auth.uid())
    where profile_id = target_profile_id;
  else
    update public.seller_verification_applications
    set status = 'rejected',
        shop_status = case when shop_status = 'not_started' then shop_status else 'rejected' end,
        reviewed_at = now(),
        reviewed_by = (select auth.uid()),
        review_reason_code = left(reason_code, 100)
    where profile_id = target_profile_id;
  end if;

  perform private.write_audit_log('admin', 'application_' || decision, target_profile_id,
    jsonb_build_object('revision', application.revision, 'reason_code', reason_code));

  return jsonb_build_object('profile_id', target_profile_id, 'decision', decision);
end;
$$;

revoke all on function public.admin_review_seller_application(bigint, integer, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_review_seller_application(bigint, integer, text, text)
  to authenticated;

-- Suspend, revoke, or restore an approved seller.
create or replace function public.admin_set_seller_account_status(
  target_profile_id bigint,
  new_status text,
  reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  if new_status not in ('active', 'suspended', 'revoked') then
    raise exception 'Unknown seller account status.' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(reason, ''))) not between 3 and 500 then
    raise exception 'A reason is required.' using errcode = '22023';
  end if;
  if target_profile_id = private.current_profile_id() then
    raise exception 'Administrators cannot change their own seller account.' using errcode = '42501';
  end if;

  update public.seller_accounts
  set status = new_status,
      status_reason = trim(reason),
      approved_by = case when new_status = 'active' then (select auth.uid()) else approved_by end,
      approved_at = case when new_status = 'active' then now() else approved_at end
  where profile_id = target_profile_id
    and approved_by is not null;
  if not found then
    raise exception 'Only previously approved seller accounts can change status.' using errcode = 'P0002';
  end if;

  update public.seller_verification_applications
  set status = case when new_status = 'active' then 'approved' else 'suspended' end
  where profile_id = target_profile_id;

  perform private.write_audit_log('admin', 'seller_account_' || new_status, target_profile_id,
    jsonb_build_object('reason', trim(reason)));
end;
$$;

revoke all on function public.admin_set_seller_account_status(bigint, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_set_seller_account_status(bigint, text, text) to authenticated;

-- The pre-onboarding service-only review endpoint must not bypass the new
-- approval path (it does not create a seller_accounts row or check identity).
revoke execute on function public.review_seller_verification(bigint, boolean, date) from service_role;
