-- Seller onboarding, identity verification, and admin approval.
--
-- Run only against a disposable local Supabase database:
--   supabase db reset
--   supabase test db supabase/tests/seller_onboarding_flow.sql
--
-- Covers: verified-account and terms requirements, server-owned fields,
-- verification sessions and the four outcomes, retry limits, webhook
-- idempotency, shop setup gating, admin-only approval tied to a revision,
-- appeals, audit-log immutability, and admin provisioning/revocation.
-- The transaction is rolled back.

begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

-- Fixtures ------------------------------------------------------------------
-- Profiles are created by the signup trigger as Buyers.

insert into auth.users
  (id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('20000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'onboard-applicant@example.test', '', now(), '{}',
   '{"first_name":"Ana","account_type":"Seller"}', now(), now()),
  ('20000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'onboard-unverified@example.test', '', null, '{}', '{}', now(), now()),
  ('20000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'onboard-admin@example.test', '', now(), '{}', '{"role":"Admin"}', now(), now()),
  ('20000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'onboard-retry@example.test', '', now(), '{}', '{}', now(), now());

-- Catalog -------------------------------------------------------------------

select extensions.ok(
  (select bool_and(relrowsecurity) from pg_class
   where oid in ('public.admin_users'::regclass, 'public.audit_logs'::regclass,
                 'public.verification_sessions'::regclass)),
  'admin_users, audit_logs, and verification_sessions have RLS enabled'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.admin_users', 'SELECT')
    and not has_table_privilege('authenticated', 'public.admin_users', 'INSERT')
    and not has_table_privilege('authenticated', 'public.admin_users', 'UPDATE'),
  'authenticated users have no access to admin_users'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.seller_verification_applications', 'INSERT')
    and not has_table_privilege('authenticated', 'public.seller_verification_applications', 'UPDATE')
    and not has_column_privilege('authenticated', 'public.seller_verification_applications', 'identity_status', 'UPDATE'),
  'authenticated users cannot write application rows directly'
);
select extensions.ok(
  not has_function_privilege('authenticated', 'public.service_record_verification_result(text, text, text, text, jsonb)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.service_attach_verification_session(uuid, text, timestamptz)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.begin_identity_verification(text)', 'EXECUTE'),
  'service-only verification functions are not callable by clients'
);
select extensions.ok(
  not has_function_privilege('service_role', 'public.review_seller_verification(bigint, boolean, date)', 'EXECUTE'),
  'the legacy review endpoint can no longer bypass the approval flow'
);

-- Step 1: account must be verified -------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select extensions.throws_ok(
  $$select public.submit_seller_application('{"sellerType":"individual","firstName":"Test","lastName":"Applicant","birthDate":"1995-05-05","address":"12 Rizal Street, Makati City","identityDocumentType":"national_id","payoutMethod":"gcash","payoutAccountName":"U","acceptedTermsVersion":"2026-10"}'::jsonb)$$,
  '42501',
  'an unverified account cannot apply'
);
reset role;

-- Step 2: apply and accept terms ---------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select extensions.throws_ok(
  $$select public.submit_seller_application('{"sellerType":"individual","firstName":"Test","lastName":"Applicant","birthDate":"1995-05-05","address":"12 Rizal Street, Makati City","identityDocumentType":"national_id","payoutMethod":"gcash","payoutAccountName":"Ana"}'::jsonb)$$,
  '22023',
  'applying without accepting the current terms is rejected'
);
select extensions.lives_ok(
  $$select public.submit_seller_application('{"sellerType":"individual","firstName":"Test","lastName":"Applicant","birthDate":"1995-05-05","address":"12 Rizal Street, Makati City","identityDocumentType":"national_id","payoutMethod":"gcash","payoutAccountName":"Ana","acceptedTermsVersion":"2026-10","identityStatus":"verified"}'::jsonb)$$,
  'a verified Buyer can apply after accepting the terms'
);
select extensions.is(
  (public.get_my_seller_onboarding() -> 'application' ->> 'identityStatus'),
  'not_started',
  'a forged identityStatus in the payload is ignored'
);
select extensions.throws_ok(
  $$update public.seller_verification_applications set identity_status = 'verified'$$,
  '42501',
  'an applicant cannot mark their own identity as verified'
);
select extensions.throws_ok(
  $$select public.save_shop_draft('{"shopName":"Ana Crafts"}'::jsonb)$$,
  '42501',
  'shop setup is blocked before identity verification'
);
select extensions.ok(not public.am_i_admin(), 'an applicant is not an admin');
select extensions.throws_ok(
  $$select * from public.admin_list_seller_applications()$$,
  '42501',
  'an applicant cannot list applications'
);
select extensions.throws_ok(
  $$select public.admin_review_seller_application(private.current_profile_id(), 1, 'approve')$$,
  '42501',
  'an applicant cannot approve themselves'
);

-- Step 3: identity verification session -------------------------------------

select extensions.lives_ok(
  $$select public.begin_identity_verification('mock')$$,
  'an applicant can start identity verification'
);
reset role;

set local role service_role;
select public.service_attach_verification_session(
  (select s.id from public.verification_sessions s join public.profiles p on p.id = s.profile_id
   where p.auth_user_id = '20000000-0000-0000-0000-000000000001' and s.status = 'created'),
  'prov-ana-1', now() + interval '30 minutes');

-- Step 4: outcomes -----------------------------------------------------------

select extensions.is(
  public.service_record_verification_result('prov-ana-1', 'evt-1', 'needs_retry', 'image_blurry', '{}'::jsonb) ->> 'status',
  'needs_retry',
  'a blurry capture asks for another attempt'
);
select extensions.ok(
  (public.service_record_verification_result('prov-ana-1', 'evt-1', 'needs_retry', 'image_blurry', '{}'::jsonb) ->> 'duplicate')::boolean,
  'a repeated webhook event is ignored'
);
reset role;

select extensions.is(
  (select identity_attempts from public.seller_verification_applications a
   join public.profiles p on p.id = a.profile_id
   where p.auth_user_id = '20000000-0000-0000-0000-000000000001'),
  1,
  'a duplicate event does not use another attempt'
);

set local role authenticated;
select extensions.lives_ok(
  $$select public.begin_identity_verification('mock')$$,
  'the applicant can retry after needs_retry'
);
reset role;

set local role service_role;
select public.service_attach_verification_session(
  (select s.id from public.verification_sessions s join public.profiles p on p.id = s.profile_id
   where p.auth_user_id = '20000000-0000-0000-0000-000000000001' and s.status = 'created'),
  'prov-ana-2', now() + interval '30 minutes');
select extensions.ok(
  (public.service_record_verification_result('prov-ana-1', 'evt-late', 'verified', null, '{}'::jsonb) ->> 'ignored')::boolean,
  'a late result for a superseded session is ignored'
);
select extensions.is(
  public.service_record_verification_result('prov-ana-2', 'evt-2', 'verified', null,
    '{"document":true,"liveness":true,"face_match":true,"raw_image":"base64..."}'::jsonb) ->> 'status',
  'verified',
  'a passing result verifies the applicant'
);
select extensions.is(
  (select checks from public.verification_sessions where provider_session_id = 'prov-ana-2'),
  '{"document":true,"liveness":true,"face_match":true}'::jsonb,
  'only boolean check flags are stored; other provider data is discarded'
);
reset role;

set local role authenticated;
select extensions.is(
  (select count(*)::integer from public.verification_sessions),
  2,
  'an applicant can read their own verification sessions'
);
select extensions.lives_ok(
  $$select public.submit_seller_application(
    '{"sellerType":"individual","firstName":"Test","lastName":"Applicant","birthDate":"1996-06-06","address":"Updated identity address","identityDocumentType":"passport","payoutMethod":"gcash","payoutAccountName":"Ana","acceptedTermsVersion":"2026-10"}'::jsonb
  )$$,
  'an applicant may correct identity details before final approval'
);
select extensions.is(
  (select identity_status from public.seller_verification_applications
   where profile_id = private.current_profile_id()),
  'not_started',
  'changing identity facts invalidates the previous verification result'
);
select extensions.throws_ok(
  $$select public.save_shop_draft('{"shopName":"Ana Crafts","shopDescription":"Hand-knitted scarves and bags","shopCategory":"Fiber and Textile Crafts","shopCity":"Quezon City","submit":true}'::jsonb)$$,
  '42501',
  'shop setup is blocked until the changed identity is verified again'
);
select extensions.lives_ok(
  $$select public.begin_identity_verification('mock')$$,
  'the applicant can verify the revised identity details'
);
reset role;

set local role service_role;
select public.service_attach_verification_session(
  (select s.id from public.verification_sessions s join public.profiles p on p.id = s.profile_id
   where p.auth_user_id = '20000000-0000-0000-0000-000000000001' and s.status = 'created'),
  'prov-ana-revised', now() + interval '30 minutes');
select extensions.is(
  public.service_record_verification_result(
    'prov-ana-revised', 'evt-revised', 'verified', null,
    '{"document":true,"liveness":true,"face_match":true}'::jsonb
  ) ->> 'status',
  'verified',
  'the provider result verifies the current application revision'
);
reset role;

set local role authenticated;
select extensions.throws_ok(
  $$select public.begin_identity_verification('mock')$$,
  '23514',
  'a verified applicant cannot start another verification'
);

-- Step 5: shop setup ---------------------------------------------------------

select extensions.throws_ok(
  $$select public.save_shop_draft('{"shopName":"Ana Crafts","submit":true}'::jsonb)$$,
  '22023',
  'submitting a shop requires description, category, and city'
);
select extensions.is(
  public.save_shop_draft('{"shopName":"Ana Crafts","shopDescription":"Hand-knitted scarves and bags","shopCategory":"Fiber and Textile Crafts","shopCity":"Quezon City","submit":true}'::jsonb) ->> 'shop_status',
  'submitted',
  'a verified applicant can submit their shop'
);
reset role;
select extensions.ok(
  not private.has_active_seller_authorization(
    (select id from public.profiles where auth_user_id = '20000000-0000-0000-0000-000000000001')),
  'a submitted shop does not grant seller permissions'
);

-- Other users cannot see the applicant's sessions.
select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
set local role authenticated;
select extensions.is(
  (select count(*)::integer from public.verification_sessions),
  0,
  'other users cannot read verification sessions'
);
reset role;

-- Step 6: admin approval -----------------------------------------------------

insert into public.admin_users (auth_user_id, granted_by)
values ('20000000-0000-0000-0000-000000000003', 'pgTAP fixture');

select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select extensions.ok(public.am_i_admin(), 'a provisioned admin is recognised');
select extensions.ok(
  (select count(*) from public.admin_list_seller_applications('under_review')) >= 1,
  'an admin can list pending applications'
);
select extensions.throws_ok(
  $$select public.admin_review_seller_application(
      (select id from public.profiles where auth_user_id = '20000000-0000-0000-0000-000000000001'),
      99, 'approve')$$,
  '40001',
  'approval of a stale application revision is refused'
);
select extensions.throws_ok(
  $$select public.admin_review_seller_application(private.current_profile_id(), 1, 'approve')$$,
  '42501',
  'an admin cannot review their own application'
);
select extensions.lives_ok(
  $$select public.admin_review_seller_application(
      (select id from public.profiles where auth_user_id = '20000000-0000-0000-0000-000000000001'),
      2, 'approve')$$,
  'an admin can approve a verified applicant with a submitted shop'
);
reset role;

select extensions.ok(
  (select sa.status = 'active' and sa.approved_by = '20000000-0000-0000-0000-000000000003'
          and p.account_type = 'Seller' and p.shop_name = 'Ana Crafts'
   from public.seller_accounts sa join public.profiles p on p.id = sa.profile_id
   where p.auth_user_id = '20000000-0000-0000-0000-000000000001'),
  'approval creates an active seller account attributed to the admin'
);
select extensions.ok(
  private.has_active_seller_authorization(
    (select id from public.profiles where auth_user_id = '20000000-0000-0000-0000-000000000001')),
  'the approved applicant now has seller authorization'
);
select extensions.ok(
  exists (select 1 from public.audit_logs l join public.profiles p on p.id = l.target_profile_id
          where p.auth_user_id = '20000000-0000-0000-0000-000000000001'
            and l.action = 'application_approve'
            and l.actor_auth_user_id = '20000000-0000-0000-0000-000000000003'),
  'approval is recorded in the audit log'
);

-- Audit log is admin-readable and append-only.
select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
set local role authenticated;
select extensions.is(
  (select count(*)::integer from public.audit_logs),
  0,
  'non-admins cannot read the audit log'
);
reset role;
set local role service_role;
select extensions.throws_ok(
  $$update public.audit_logs set action = 'tampered'$$,
  '42501',
  'audit log entries cannot be modified, even by the service role'
);
reset role;

-- Retry limit, manual review, rejection, and appeal --------------------------

select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
set local role authenticated;
select public.submit_seller_application('{"sellerType":"individual","firstName":"Test","lastName":"Applicant","birthDate":"1990-01-01","address":"45 Mabini Avenue, Cebu City","identityDocumentType":"passport","payoutMethod":"bank","payoutAccountName":"Ben","acceptedTermsVersion":"2026-10"}'::jsonb);
select public.begin_identity_verification('mock');
reset role;
set local role service_role;
select public.service_attach_verification_session(
  (select s.id from public.verification_sessions s join public.profiles p on p.id = s.profile_id
   where p.auth_user_id = '20000000-0000-0000-0000-000000000004' and s.status = 'created'),
  'prov-ben-1', now() + interval '30 minutes');
select public.service_record_verification_result('prov-ben-1', 'b-1', 'needs_retry', 'capture_failed', '{}'::jsonb);
reset role;

set local role authenticated;
select public.begin_identity_verification('mock');
reset role;
set local role service_role;
select public.service_attach_verification_session(
  (select s.id from public.verification_sessions s join public.profiles p on p.id = s.profile_id
   where p.auth_user_id = '20000000-0000-0000-0000-000000000004' and s.status = 'created'),
  'prov-ben-2', now() + interval '30 minutes');
select public.service_record_verification_result('prov-ben-2', 'b-2', 'needs_retry', 'capture_failed', '{}'::jsonb);
reset role;

set local role authenticated;
select public.begin_identity_verification('mock');
reset role;
set local role service_role;
select public.service_attach_verification_session(
  (select s.id from public.verification_sessions s join public.profiles p on p.id = s.profile_id
   where p.auth_user_id = '20000000-0000-0000-0000-000000000004' and s.status = 'created'),
  'prov-ben-3', now() + interval '30 minutes');
select extensions.is(
  public.service_record_verification_result('prov-ben-3', 'b-3', 'needs_retry', 'capture_failed', '{}'::jsonb) ->> 'status',
  'under_review',
  'the final failed attempt moves the case to manual review'
);
reset role;

set local role authenticated;
select extensions.throws_ok(
  $$select public.begin_identity_verification('mock')$$,
  '23514',
  'no further attempts are allowed while under manual review'
);
reset role;

select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select extensions.lives_ok(
  $$select public.admin_resolve_identity_review(
      (select id from public.profiles where auth_user_id = '20000000-0000-0000-0000-000000000004'),
      false, 'face_mismatch')$$,
  'an admin can resolve a manual identity review'
);
reset role;

select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
set local role authenticated;
select extensions.is(
  public.get_my_seller_onboarding() -> 'application' ->> 'status',
  'rejected',
  'a failed identity review closes the application'
);
select extensions.throws_ok(
  $$select public.submit_seller_application('{"sellerType":"individual","firstName":"Test","lastName":"Applicant","birthDate":"1990-01-01","address":"45 Mabini Avenue, Cebu City","identityDocumentType":"passport","payoutMethod":"bank","payoutAccountName":"Ben","acceptedTermsVersion":"2026-10"}'::jsonb)$$,
  '23514',
  'a failed identity check cannot be bypassed by resubmitting'
);
select extensions.throws_ok(
  $$select public.appeal_seller_application('short')$$,
  '22023',
  'an appeal needs an explanation'
);
select extensions.lives_ok(
  $$select public.appeal_seller_application('My camera was broken; I can retry with a new phone.')$$,
  'a rejected applicant can appeal'
);
reset role;

select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select extensions.lives_ok(
  $$select public.admin_review_seller_application(
      (select id from public.profiles where auth_user_id = '20000000-0000-0000-0000-000000000004'),
      1, 'request_changes', 'capture_failed')$$,
  'an admin can reopen an appealed application'
);
reset role;

select extensions.ok(
  (select a.status = 'under_review' and a.identity_status = 'needs_retry' and a.identity_attempts = 0
   from public.seller_verification_applications a join public.profiles p on p.id = a.profile_id
   where p.auth_user_id = '20000000-0000-0000-0000-000000000004'),
  'a reopened application gets fresh identity attempts'
);

-- Admin revocation -----------------------------------------------------------

update public.admin_users set revoked_at = now()
where auth_user_id = '20000000-0000-0000-0000-000000000003';
select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select extensions.ok(not public.am_i_admin(), 'a revoked admin loses access immediately');
select extensions.throws_ok(
  $$select * from public.admin_list_seller_applications()$$,
  '42501',
  'a revoked admin cannot list applications'
);
reset role;

select * from extensions.finish();
rollback;
