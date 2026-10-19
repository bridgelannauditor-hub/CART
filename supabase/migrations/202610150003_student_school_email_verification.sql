-- Trusted school-email verification for student Seller applications.
-- Codes are generated and emailed by Edge Functions. PostgreSQL stores only
-- an HMAC digest and binds every challenge to the current application revision.

begin;

create table public.school_email_verification_challenges (
  id uuid primary key default gen_random_uuid(),
  profile_id bigint not null references public.profiles(id) on delete cascade,
  application_revision integer not null,
  school_email text not null,
  code_hash text not null check (code_hash ~ '^[0-9a-f]{64}$'),
  attempts integer not null default 0 check (attempts between 0 and 5),
  expires_at timestamptz not null,
  verified_at timestamptz,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint school_email_challenge_expiry check (expires_at > created_at),
  constraint school_email_challenge_completion check (
    verified_at is null or consumed_at is not null
  )
);

create index school_email_challenges_profile_created_idx
  on public.school_email_verification_challenges (profile_id, created_at desc);

comment on table public.school_email_verification_challenges is
  'Short-lived, revision-bound school-email challenges. Codes are stored only as keyed HMAC digests.';

alter table public.school_email_verification_challenges enable row level security;
revoke all on table public.school_email_verification_challenges
  from public, anon, authenticated;
grant all on table public.school_email_verification_challenges to service_role;

-- Keep the compatibility profile flag conservative whenever an application is
-- created, resubmitted, or verified. The application remains the approval
-- source of truth.
create or replace function private.sync_school_email_verification_flag()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set school_email_verified = (
    new.seller_type = 'student' and new.school_email_verified
  )
  where id = new.profile_id;
  return new;
end;
$$;

revoke all on function private.sync_school_email_verification_flag()
  from public, anon, authenticated;

drop trigger if exists sync_school_email_verification_flag
  on public.seller_verification_applications;
create trigger sync_school_email_verification_flag
after insert or update of seller_type, school_email, school_email_verified
on public.seller_verification_applications
for each row execute function private.sync_school_email_verification_flag();

create or replace function public.service_create_school_email_challenge(
  requested_challenge_id uuid,
  target_auth_user_id uuid,
  expected_email text,
  expected_revision integer,
  challenge_hash text,
  challenge_expires_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile_id bigint;
  application public.seller_verification_applications%rowtype;
begin
  select p.id into target_profile_id
  from public.profiles p
  where p.auth_user_id = target_auth_user_id;
  if target_profile_id is null then
    raise exception 'Applicant profile was not found.' using errcode = 'P0002';
  end if;

  select * into application
  from public.seller_verification_applications a
  where a.profile_id = target_profile_id
  for update;

  if not found or application.seller_type <> 'student'
     or application.status <> 'under_review'
     or application.school_email_verified then
    raise exception 'School-email verification is not available.' using errcode = '23514';
  end if;
  if application.revision <> expected_revision
     or lower(application.school_email) <> lower(trim(expected_email)) then
    raise exception 'The application changed. Reload it and try again.' using errcode = '40001';
  end if;
  if challenge_hash !~ '^[0-9a-f]{64}$'
     or challenge_expires_at <= now()
     or challenge_expires_at > now() + interval '15 minutes' then
    raise exception 'Invalid challenge.' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.school_email_verification_challenges c
    where c.profile_id = target_profile_id
      and c.created_at > now() - interval '60 seconds'
  ) or (
    select count(*) from public.school_email_verification_challenges c
    where c.profile_id = target_profile_id
      and c.created_at > now() - interval '1 hour'
  ) >= 3 then
    raise exception 'Please wait before requesting another code.' using errcode = 'P0001';
  end if;

  update public.school_email_verification_challenges
  set consumed_at = coalesce(consumed_at, now())
  where profile_id = target_profile_id and consumed_at is null;

  insert into public.school_email_verification_challenges (
    id, profile_id, application_revision, school_email, code_hash, expires_at
  ) values (
    requested_challenge_id, target_profile_id, expected_revision, lower(trim(expected_email)),
    challenge_hash, challenge_expires_at
  );

  perform private.write_audit_log(
    'service', 'school_email_challenge_created', target_profile_id,
    jsonb_build_object('application_revision', expected_revision)
  );
  return requested_challenge_id;
end;
$$;

revoke all on function public.service_create_school_email_challenge(
  uuid, uuid, text, integer, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.service_create_school_email_challenge(
  uuid, uuid, text, integer, text, timestamptz
) to service_role;

create or replace function public.service_cancel_school_email_challenge(
  challenge_id uuid,
  target_auth_user_id uuid
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.school_email_verification_challenges c
  set consumed_at = coalesce(c.consumed_at, now())
  from public.profiles p
  where c.id = challenge_id
    and p.id = c.profile_id
    and p.auth_user_id = target_auth_user_id;
$$;

revoke all on function public.service_cancel_school_email_challenge(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.service_cancel_school_email_challenge(uuid, uuid)
  to service_role;

create or replace function public.service_verify_school_email_challenge(
  challenge_id uuid,
  target_auth_user_id uuid,
  submitted_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile_id bigint;
  challenge public.school_email_verification_challenges%rowtype;
  application public.seller_verification_applications%rowtype;
begin
  select p.id into target_profile_id
  from public.profiles p
  where p.auth_user_id = target_auth_user_id;

  select * into challenge
  from public.school_email_verification_challenges c
  where c.id = challenge_id and c.profile_id = target_profile_id
  for update;

  if not found or challenge.consumed_at is not null then
    return jsonb_build_object('verified', false, 'reason', 'invalid');
  end if;
  if challenge.expires_at <= now() then
    update public.school_email_verification_challenges
    set consumed_at = now() where id = challenge.id;
    return jsonb_build_object('verified', false, 'reason', 'expired');
  end if;
  if challenge.attempts >= 5 then
    update public.school_email_verification_challenges
    set consumed_at = now() where id = challenge.id;
    return jsonb_build_object('verified', false, 'reason', 'attempts_exhausted');
  end if;
  if challenge.code_hash <> lower(submitted_hash) then
    update public.school_email_verification_challenges
    set attempts = attempts + 1,
        consumed_at = case when attempts + 1 >= 5 then now() else consumed_at end
    where id = challenge.id;
    return jsonb_build_object(
      'verified', false,
      'reason', case when challenge.attempts + 1 >= 5 then 'attempts_exhausted' else 'incorrect' end,
      'attemptsRemaining', greatest(0, 5 - challenge.attempts - 1)
    );
  end if;

  select * into application
  from public.seller_verification_applications a
  where a.profile_id = target_profile_id
  for update;
  if not found
     or application.seller_type <> 'student'
     or application.status <> 'under_review'
     or application.revision <> challenge.application_revision
     or lower(application.school_email) <> challenge.school_email then
    update public.school_email_verification_challenges
    set consumed_at = now() where id = challenge.id;
    return jsonb_build_object('verified', false, 'reason', 'application_changed');
  end if;

  update public.seller_verification_applications
  set school_email_verified = true
  where profile_id = target_profile_id;
  update public.school_email_verification_challenges
  set verified_at = now(), consumed_at = now()
  where id = challenge.id;

  perform private.write_audit_log(
    'service', 'school_email_verified', target_profile_id,
    jsonb_build_object('application_revision', application.revision)
  );
  return jsonb_build_object('verified', true);
end;
$$;

revoke all on function public.service_verify_school_email_challenge(
  uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.service_verify_school_email_challenge(
  uuid, uuid, text
) to service_role;

-- Include only the signed-in applicant's school verification state.
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
  into email_verified from auth.users u where u.id = (select auth.uid());
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
      'schoolEmail', application.school_email,
      'schoolEmailVerified', application.school_email_verified,
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

revoke all on function public.get_my_seller_onboarding()
  from public, anon, authenticated;
grant execute on function public.get_my_seller_onboarding() to authenticated;

commit;
