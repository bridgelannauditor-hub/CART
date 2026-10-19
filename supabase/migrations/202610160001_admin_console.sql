-- Protected administration console queries. All functions require membership
-- in public.admin_users and expose only the fields needed by the admin UI.

create or replace function public.admin_dashboard_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'active_sellers', (select count(*) from public.seller_accounts where status = 'active'),
    'pending_applications', (select count(*) from public.seller_verification_applications where status in ('under_review', 'appealed')),
    'open_reports', (select count(*) from public.listing_reports where status in ('open', 'reviewing')),
    'orders', (select count(*) from public.orders),
    'products', (select count(*) from public.products)
  );
end;
$$;

revoke all on function public.admin_dashboard_summary() from public, anon, authenticated;
grant execute on function public.admin_dashboard_summary() to authenticated;

create or replace function public.admin_list_profiles(
  search_query text default null,
  row_limit integer default 100
)
returns table (
  profile_id bigint,
  first_name text,
  last_name text,
  email text,
  account_type text,
  shop_name text,
  is_verified_seller boolean,
  seller_status text,
  is_admin boolean,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select p.id, p.first_name, p.last_name, p.email, p.account_type, p.shop_name,
         p.is_verified_seller, sa.status,
         exists (select 1 from public.admin_users a where a.auth_user_id = p.auth_user_id and a.revoked_at is null),
         p.created_at
  from public.profiles p
  left join public.seller_accounts sa on sa.profile_id = p.id
  where nullif(trim(search_query), '') is null
     or concat_ws(' ', p.first_name, p.last_name, p.email, p.shop_name) ilike '%' || trim(search_query) || '%'
  order by p.created_at desc
  limit least(greatest(coalesce(row_limit, 100), 1), 250);
end;
$$;

revoke all on function public.admin_list_profiles(text, integer) from public, anon, authenticated;
grant execute on function public.admin_list_profiles(text, integer) to authenticated;

create or replace function public.admin_list_listing_reports(status_filter text default null)
returns table (
  report_id bigint,
  product_id bigint,
  product_name text,
  seller_id bigint,
  reporter_id bigint,
  reason text,
  details text,
  status text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  if status_filter is not null and status_filter not in ('open', 'reviewing', 'resolved', 'dismissed') then
    raise exception 'Invalid report status.' using errcode = '22023';
  end if;
  return query
  select r.id, r.product_id, p.product_name, p.seller_id, r.reporter_id,
         r.reason, r.details, r.status, r.created_at
  from public.listing_reports r
  join public.products p on p.id = r.product_id
  where status_filter is null or r.status = status_filter
  order by r.created_at desc
  limit 250;
end;
$$;

revoke all on function public.admin_list_listing_reports(text) from public, anon, authenticated;
grant execute on function public.admin_list_listing_reports(text) to authenticated;

create or replace function public.admin_update_listing_report(
  target_report_id bigint,
  new_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_profile_id bigint;
begin
  perform private.require_admin();
  if new_status not in ('open', 'reviewing', 'resolved', 'dismissed') then
    raise exception 'Invalid report status.' using errcode = '22023';
  end if;

  update public.listing_reports r
  set status = new_status
  where r.id = target_report_id
  returning r.reporter_id into affected_profile_id;

  if affected_profile_id is null then
    raise exception 'Report not found.' using errcode = 'P0002';
  end if;

  perform private.write_audit_log(
    'admin',
    'listing_report_' || new_status,
    affected_profile_id,
    jsonb_build_object('report_id', target_report_id)
  );
end;
$$;

revoke all on function public.admin_update_listing_report(bigint, text) from public, anon, authenticated;
grant execute on function public.admin_update_listing_report(bigint, text) to authenticated;
