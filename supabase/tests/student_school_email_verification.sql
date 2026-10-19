-- Run only against a disposable database after all migrations.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '30000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
  'student-applicant@example.test', '', now(), '{}', '{}', now(), now()
);

select extensions.ok(
  (select relrowsecurity from pg_class
   where oid = 'public.school_email_verification_challenges'::regclass),
  'school email challenges have RLS enabled'
);
select extensions.ok(
  not has_table_privilege(
    'authenticated', 'public.school_email_verification_challenges', 'SELECT'
  ) and not has_table_privilege(
    'authenticated', 'public.school_email_verification_challenges', 'INSERT'
  ),
  'challenge secrets are not available to authenticated clients'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.service_create_school_email_challenge(uuid,uuid,text,integer,text,timestamptz)',
    'EXECUTE'
  ) and not has_function_privilege(
    'authenticated',
    'public.service_verify_school_email_challenge(uuid,uuid,text)',
    'EXECUTE'
  ),
  'challenge creation and verification are service-only'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select public.submit_seller_application(
  '{"sellerType":"student","firstName":"Test","lastName":"Applicant","birthDate":"2001-05-05","address":"Quezon City","identityDocumentType":"student_id","payoutMethod":"gcash","payoutAccountName":"Student Applicant","schoolEmail":"student@university.edu.ph","acceptedTermsVersion":"2026-10"}'::jsonb
);
select extensions.is(
  public.get_my_seller_onboarding() -> 'application' ->> 'schoolEmailVerified',
  'false',
  'student school email starts unverified'
);
reset role;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select public.service_create_school_email_challenge(
  '30000000-0000-0000-0000-000000000101',
  '30000000-0000-0000-0000-000000000001',
  'student@university.edu.ph', 1, repeat('a', 64),
  now() + interval '10 minutes'
);
select extensions.is(
  public.service_verify_school_email_challenge(
    '30000000-0000-0000-0000-000000000101',
    '30000000-0000-0000-0000-000000000001', repeat('b', 64)
  ) ->> 'reason',
  'incorrect',
  'an incorrect code digest is rejected'
);
select extensions.ok(
  (public.service_verify_school_email_challenge(
    '30000000-0000-0000-0000-000000000101',
    '30000000-0000-0000-0000-000000000001', repeat('a', 64)
  ) ->> 'verified')::boolean,
  'the matching challenge verifies the current school email'
);
reset role;

select extensions.ok(
  (select a.school_email_verified and p.school_email_verified
   from public.seller_verification_applications a
   join public.profiles p on p.id = a.profile_id
   where p.auth_user_id = '30000000-0000-0000-0000-000000000001'),
  'verification updates the application and compatible profile trust flag'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select public.submit_seller_application(
  '{"sellerType":"student","firstName":"Test","lastName":"Applicant","birthDate":"2001-05-05","address":"Quezon City","identityDocumentType":"student_id","payoutMethod":"gcash","payoutAccountName":"Student Applicant","schoolEmail":"student@university.edu.ph","acceptedTermsVersion":"2026-10"}'::jsonb
);
reset role;

set local role service_role;
update public.school_email_verification_challenges
set created_at = created_at - interval '2 minutes';
select public.service_create_school_email_challenge(
  '30000000-0000-0000-0000-000000000102',
  '30000000-0000-0000-0000-000000000001',
  'student@university.edu.ph', 2, repeat('c', 64),
  now() + interval '10 minutes'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select public.submit_seller_application(
  '{"sellerType":"student","firstName":"Test","lastName":"Applicant","birthDate":"2001-05-05","address":"Quezon City","identityDocumentType":"student_id","payoutMethod":"gcash","payoutAccountName":"Student Applicant","schoolEmail":"student2@university.edu.ph","acceptedTermsVersion":"2026-10"}'::jsonb
);
reset role;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select extensions.is(
  public.service_verify_school_email_challenge(
    '30000000-0000-0000-0000-000000000102',
    '30000000-0000-0000-0000-000000000001', repeat('c', 64)
  ) ->> 'reason',
  'application_changed',
  'a code cannot verify a changed school email or application revision'
);
reset role;

select extensions.ok(
  not (select a.school_email_verified
       from public.seller_verification_applications a
       join public.profiles p on p.id = a.profile_id
       where p.auth_user_id = '30000000-0000-0000-0000-000000000001'),
  'changing the application leaves the new school address unverified'
);

select * from extensions.finish();
rollback;
