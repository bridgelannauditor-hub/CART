-- Suspension reasons by behavior, with an automatic evidence record.
--
-- An administrator still decides whether to suspend, but every suspension now
-- records WHY: the categories chosen (inappropriate products, reports from
-- users, other) plus a server-built snapshot of the account's open and past
-- reports at that moment. The snapshot is computed here, never taken from the
-- client, so the record cannot be edited or left out.

alter table public.account_suspensions
  add column categories text[] not null default '{}',
  add column evidence jsonb;

-- Reports against the account. Dismissed reports are not counted as evidence.
create or replace function private.account_evidence(target_profile_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with listing as (
    select r.id, r.product_id, p.product_name, r.reason, r.status, r.created_at
    from public.listing_reports r
    join public.products p on p.id = r.product_id
    where p.seller_id = account_evidence.target_profile_id
      and r.status <> 'dismissed'
  ),
  shop as (
    select r.id, r.reason, r.status, r.created_at
    from public.shop_reports r
    where r.shop_id = account_evidence.target_profile_id
      and r.status <> 'dismissed'
  )
  select jsonb_build_object(
    'listing_reports', jsonb_build_object(
      'total', (select count(*) from listing),
      'open', (select count(*) from listing where status in ('open', 'reviewing')),
      'by_reason', coalesce(
        (select jsonb_object_agg(g.reason, g.n)
         from (select reason, count(*) as n from listing group by reason) g),
        '{}'::jsonb),
      'items', coalesce(
        (select jsonb_agg(to_jsonb(i))
         from (select id as report_id, product_id, product_name, reason, status, created_at
               from listing order by created_at desc limit 10) i),
        '[]'::jsonb)
    ),
    'shop_reports', jsonb_build_object(
      'total', (select count(*) from shop),
      'open', (select count(*) from shop where status in ('open', 'reviewing')),
      'by_reason', coalesce(
        (select jsonb_object_agg(g.reason, g.n)
         from (select reason, count(*) as n from shop group by reason) g),
        '{}'::jsonb),
      'items', coalesce(
        (select jsonb_agg(to_jsonb(i))
         from (select id as report_id, reason, status, created_at
               from shop order by created_at desc limit 10) i),
        '[]'::jsonb)
    ),
    'suggested_categories', (
      select coalesce(jsonb_agg(s.category), '[]'::jsonb)
      from (
        select 'inappropriate_products' as category where exists (select 1 from listing)
        union all
        select 'user_reports' where exists (select 1 from shop)
      ) s
    ),
    'captured_at', now()
  );
$$;
revoke all on function private.account_evidence(bigint) from public, anon, authenticated;

-- What the suspend dialog shows before the administrator decides.
create or replace function public.admin_account_evidence(target_profile_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return private.account_evidence(admin_account_evidence.target_profile_id);
end;
$$;
revoke all on function public.admin_account_evidence(bigint) from public, anon;
grant execute on function public.admin_account_evidence(bigint) to authenticated;

-- The signature gains a categories argument, so the old function is replaced.
drop function public.admin_set_account_suspension(bigint, boolean, text);
create function public.admin_set_account_suspension(
  target_profile_id bigint,
  suspend boolean,
  reason text,
  categories text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_row public.profiles;
  seller_status text;
  clean_reason text := trim(coalesce(admin_set_account_suspension.reason, ''));
  clean_categories text[];
  evidence_snapshot jsonb;
begin
  perform private.require_admin();
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason is required.' using errcode = '22023';
  end if;
  if target_profile_id = private.current_profile_id() then
    raise exception 'Administrators cannot suspend their own account.' using errcode = '42501';
  end if;
  select * into profile_row from public.profiles where id = target_profile_id;
  if not found then
    raise exception 'Account not found.' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from public.admin_users a
    where a.auth_user_id = profile_row.auth_user_id and a.revoked_at is null
  ) then
    raise exception 'Administrator accounts cannot be suspended.' using errcode = '42501';
  end if;

  if suspend then
    select coalesce(array_agg(distinct c order by c), '{}')
    into clean_categories
    from unnest(coalesce(admin_set_account_suspension.categories, '{}')) as c;
    if cardinality(clean_categories) = 0 then
      raise exception 'Choose at least one reason category.' using errcode = '22023';
    end if;
    if exists (
      select 1 from unnest(clean_categories) as c
      where c not in ('inappropriate_products', 'user_reports', 'other')
    ) then
      raise exception 'Unknown reason category.' using errcode = '22023';
    end if;
    if private.is_suspended(target_profile_id) then
      raise exception 'This account is already suspended.' using errcode = '23514';
    end if;
    evidence_snapshot := private.account_evidence(target_profile_id);
    insert into public.account_suspensions
      (profile_id, reason, categories, evidence, suspended_by)
    values
      (target_profile_id, clean_reason, clean_categories, evidence_snapshot, (select auth.uid()));
  else
    update public.account_suspensions
    set lifted_at = now(), lifted_by = (select auth.uid()), lift_reason = clean_reason
    where profile_id = target_profile_id and lifted_at is null;
    if not found then
      raise exception 'This account is not suspended.' using errcode = '23514';
    end if;
  end if;

  select status into seller_status from public.seller_accounts
  where profile_id = target_profile_id and approved_by is not null;
  if suspend and seller_status = 'active' then
    perform public.admin_set_seller_account_status(target_profile_id, 'suspended', clean_reason);
  elsif not suspend and seller_status = 'suspended' then
    perform public.admin_set_seller_account_status(target_profile_id, 'active', clean_reason);
  end if;

  perform private.write_audit_log(
    'admin',
    case when suspend then 'account_suspended' else 'account_restored' end,
    target_profile_id,
    case when suspend
      then jsonb_build_object(
        'reason', clean_reason,
        'categories', to_jsonb(clean_categories),
        'evidence', evidence_snapshot)
      else jsonb_build_object('reason', clean_reason)
    end
  );
end;
$$;
revoke all on function public.admin_set_account_suspension(bigint, boolean, text, text[])
  from public, anon;
grant execute on function public.admin_set_account_suspension(bigint, boolean, text, text[])
  to authenticated;

-- The suspended user sees the categories along with the reason.
create or replace function public.my_suspension()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select jsonb_build_object(
       'suspended', true, 'reason', s.reason, 'categories', to_jsonb(s.categories))
     from public.account_suspensions s
     where s.profile_id = private.current_profile_id() and s.lifted_at is null),
    jsonb_build_object('suspended', false)
  );
$$;

-- History now returns the recorded categories and evidence for suspensions.
drop function public.admin_account_history(bigint, integer);
create function public.admin_account_history(
  target_profile_id bigint,
  row_limit integer default 100
)
returns table (
  event_id bigint,
  action text,
  actor_kind text,
  actor_email text,
  reason text,
  occurred_at timestamptz,
  details jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select l.id, l.action, l.actor_kind, p.email,
         nullif(trim(coalesce(l.details ->> 'reason', l.details ->> 'note', '')), ''),
         l.created_at,
         case when l.action in ('account_suspended', 'account_restored')
              then l.details end
  from public.audit_logs l
  left join public.profiles p on p.auth_user_id = l.actor_auth_user_id
  where l.target_profile_id = admin_account_history.target_profile_id
    and l.action in (
      'account_suspended', 'account_restored',
      'seller_account_suspended', 'seller_account_active', 'seller_account_revoked',
      'application_submitted', 'application_approve', 'application_reject',
      'application_appealed', 'shop_submitted', 'identity_review_resolved'
    )
  order by l.created_at desc, l.id desc
  limit least(greatest(coalesce(admin_account_history.row_limit, 100), 1), 500);
end;
$$;
revoke all on function public.admin_account_history(bigint, integer) from public, anon;
grant execute on function public.admin_account_history(bigint, integer) to authenticated;
