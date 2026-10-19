-- In-app ID capture for Seller verification.
--
-- Applicants photograph the front of their ID (plus the back, when the ID has
-- one) and a selfie. The images go to a PRIVATE storage bucket, readable only
-- by the applicant who uploaded them and by administrators, and the case is
-- queued as identity_status = 'under_review' for a manual admin decision
-- (admin_resolve_identity_review, or admin_request_identity_retry below).

-- ---------------------------------------------------------------------------
-- Private bucket: 5 MB, JPEG/PNG only, never public.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'seller-verification', 'seller-verification', false, 5242880,
  array['image/jpeg', 'image/png']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists seller_verification_insert_own on storage.objects;
drop policy if exists seller_verification_update_own on storage.objects;
drop policy if exists seller_verification_read_own on storage.objects;
drop policy if exists seller_verification_read_admin on storage.objects;

-- Files must live under a folder named after the uploader's auth user id.
create policy seller_verification_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'seller-verification'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy seller_verification_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'seller-verification'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'seller-verification'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy seller_verification_read_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'seller-verification'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy seller_verification_read_admin on storage.objects
  for select to authenticated
  using (bucket_id = 'seller-verification' and (select private.is_admin()));

-- ---------------------------------------------------------------------------
-- Applicant submits the uploaded photos.
-- ---------------------------------------------------------------------------
create or replace function public.submit_identity_documents(
  front_path text,
  selfie_path text,
  back_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_profile_id bigint := private.current_profile_id();
  caller_folder text := (select auth.uid())::text || '/';
  limits jsonb := private.seller_onboarding_limits();
  application public.seller_verification_applications%rowtype;
  p text;
begin
  if caller_profile_id is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  foreach p in array array[front_path, selfie_path, back_path] loop
    if p is not null then
      if left(p, char_length(caller_folder)) <> caller_folder or p like '%..%' then
        raise exception 'Invalid photo location.' using errcode = '22023';
      end if;
      if not exists (
        select 1 from storage.objects o
        where o.bucket_id = 'seller-verification' and o.name = p
      ) then
        raise exception 'A photo was not uploaded. Please try again.' using errcode = 'P0002';
      end if;
    end if;
  end loop;

  select * into application
  from public.seller_verification_applications
  where profile_id = caller_profile_id
  for update;

  if not found or application.terms_accepted_at is null then
    raise exception 'Submit the Seller application and accept the terms first.' using errcode = '23514';
  end if;
  if application.status <> 'under_review' then
    raise exception 'Identity verification is not available for this application.' using errcode = '23514';
  end if;
  if application.identity_status not in ('not_started', 'pending', 'needs_retry') then
    raise exception 'Identity photos cannot be submitted in the current state.' using errcode = '23514';
  end if;
  if application.identity_attempts >= (limits ->> 'max_identity_attempts')::integer then
    raise exception 'No verification attempts remain. The application is waiting for manual review.' using errcode = '23514';
  end if;

  insert into public.seller_verification_vault (profile_id, identity_document_path, encrypted_metadata)
  values (
    caller_profile_id, front_path,
    jsonb_build_object(
      'backPath', back_path, 'selfiePath', selfie_path,
      'revision', application.revision, 'capturedAt', now()
    )
  )
  on conflict (profile_id) do update
  set identity_document_path = excluded.identity_document_path,
      encrypted_metadata = excluded.encrypted_metadata;

  update public.seller_verification_applications
  set identity_status = 'under_review',
      identity_reason_code = 'manual_review_pending'
  where profile_id = caller_profile_id;

  perform private.write_audit_log('applicant', 'identity_documents_submitted', caller_profile_id,
    jsonb_build_object('revision', application.revision, 'has_back', back_path is not null));

  return jsonb_build_object('identity_status', 'under_review');
end;
$$;

revoke all on function public.submit_identity_documents(text, text, text)
  from public, anon, authenticated;
grant execute on function public.submit_identity_documents(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Admin: locate an applicant's photos (the app then signs short-lived URLs).
-- Every view is written to the audit log.
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_identity_document_paths(target_profile_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  vault public.seller_verification_vault%rowtype;
begin
  perform private.require_admin();

  select * into vault
  from public.seller_verification_vault
  where profile_id = target_profile_id;
  if not found or vault.identity_document_path is null then
    raise exception 'No identity photos were submitted.' using errcode = 'P0002';
  end if;

  perform private.write_audit_log('admin', 'identity_documents_viewed', target_profile_id, '{}'::jsonb);

  return jsonb_build_object(
    'front', vault.identity_document_path,
    'back', vault.encrypted_metadata ->> 'backPath',
    'selfie', vault.encrypted_metadata ->> 'selfiePath'
  );
end;
$$;

revoke all on function public.admin_get_identity_document_paths(bigint)
  from public, anon, authenticated;
grant execute on function public.admin_get_identity_document_paths(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- Admin: ask the applicant to retake the photos (uses one attempt) instead of
-- rejecting the whole application.
-- ---------------------------------------------------------------------------
create or replace function public.admin_request_identity_retry(
  target_profile_id bigint,
  reason_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  application public.seller_verification_applications%rowtype;
  max_attempts integer := (private.seller_onboarding_limits() ->> 'max_identity_attempts')::integer;
begin
  perform private.require_admin();
  if target_profile_id = private.current_profile_id() then
    raise exception 'Administrators cannot review their own application.' using errcode = '42501';
  end if;

  select * into application
  from public.seller_verification_applications
  where profile_id = target_profile_id and identity_status = 'under_review'
  for update;
  if not found then
    raise exception 'No identity review is pending for this applicant.' using errcode = 'P0002';
  end if;
  if application.identity_attempts + 1 >= max_attempts then
    raise exception 'No retries remain for this applicant. Approve or reject the identity check.' using errcode = '23514';
  end if;

  update public.seller_verification_applications
  set identity_status = 'needs_retry',
      identity_attempts = identity_attempts + 1,
      identity_reason_code = left(reason_code, 100)
  where profile_id = target_profile_id;

  perform private.write_audit_log('admin', 'identity_retry_requested', target_profile_id,
    jsonb_build_object('reason_code', reason_code));
end;
$$;

revoke all on function public.admin_request_identity_retry(bigint, text)
  from public, anon, authenticated;
grant execute on function public.admin_request_identity_retry(bigint, text) to authenticated;
