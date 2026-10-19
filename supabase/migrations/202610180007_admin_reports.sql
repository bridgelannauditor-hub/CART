-- Better admin reports.
--
-- * Listing reports now include the product picture and the seller and
--   reporter names, so a report can be read without looking up ids.
-- * Store reports ("Report store") were stored but administrators had no way
--   to read or act on them. They get a list and a status update.
-- * Report counts per status for both kinds, and the Overview "open reports"
--   figure now includes store reports.

drop function public.admin_list_listing_reports(text);
create function public.admin_list_listing_reports(status_filter text default null)
returns table (
  report_id bigint,
  product_id bigint,
  product_name text,
  product_image text,
  seller_id bigint,
  seller_name text,
  reporter_id bigint,
  reporter_name text,
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
  if status_filter is not null
     and status_filter not in ('open', 'reviewing', 'resolved', 'dismissed') then
    raise exception 'Invalid report status.' using errcode = '22023';
  end if;
  return query
  select r.id, r.product_id, p.product_name, p.image, p.seller_id,
         coalesce(nullif(trim(s.shop_name), ''), nullif(trim(s.first_name || ' ' || s.last_name), ''), 'Seller ' || s.id),
         r.reporter_id,
         coalesce(nullif(trim(rp.first_name || ' ' || rp.last_name), ''), 'User ' || rp.id),
         r.reason, r.details, r.status, r.created_at
  from public.listing_reports r
  join public.products p on p.id = r.product_id
  join public.profiles s on s.id = p.seller_id
  join public.profiles rp on rp.id = r.reporter_id
  where status_filter is null or r.status = status_filter
  order by r.created_at desc
  limit 250;
end;
$$;
revoke all on function public.admin_list_listing_reports(text) from public, anon;
grant execute on function public.admin_list_listing_reports(text) to authenticated;

create function public.admin_list_shop_reports(status_filter text default null)
returns table (
  report_id bigint,
  shop_id bigint,
  shop_name text,
  reporter_id bigint,
  reporter_name text,
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
  if status_filter is not null
     and status_filter not in ('open', 'reviewing', 'resolved', 'dismissed') then
    raise exception 'Invalid report status.' using errcode = '22023';
  end if;
  return query
  select r.id, r.shop_id,
         coalesce(nullif(trim(s.shop_name), ''), nullif(trim(s.first_name || ' ' || s.last_name), ''), 'Seller ' || s.id),
         r.reporter_id,
         coalesce(nullif(trim(rp.first_name || ' ' || rp.last_name), ''), 'User ' || rp.id),
         r.reason, r.details, r.status, r.created_at
  from public.shop_reports r
  join public.profiles s on s.id = r.shop_id
  join public.profiles rp on rp.id = r.reporter_id
  where status_filter is null or r.status = status_filter
  order by r.created_at desc
  limit 250;
end;
$$;
revoke all on function public.admin_list_shop_reports(text) from public, anon;
grant execute on function public.admin_list_shop_reports(text) to authenticated;

create function public.admin_update_shop_report(target_report_id bigint, new_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  reported_shop_id bigint;
begin
  perform private.require_admin();
  if new_status not in ('open', 'reviewing', 'resolved', 'dismissed') then
    raise exception 'Invalid report status.' using errcode = '22023';
  end if;
  update public.shop_reports r
  set status = new_status
  where r.id = target_report_id
  returning r.shop_id into reported_shop_id;
  if reported_shop_id is null then
    raise exception 'Report not found.' using errcode = 'P0002';
  end if;
  perform private.write_audit_log(
    'admin', 'shop_report_' || new_status, reported_shop_id,
    jsonb_build_object('report_id', target_report_id));
end;
$$;
revoke all on function public.admin_update_shop_report(bigint, text) from public, anon;
grant execute on function public.admin_update_shop_report(bigint, text) to authenticated;

-- Number of reports in each status, for the filter badges.
create function public.admin_report_counts()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return jsonb_build_object(
    'listing', jsonb_build_object(
      'open', (select count(*) from public.listing_reports where status = 'open'),
      'reviewing', (select count(*) from public.listing_reports where status = 'reviewing'),
      'resolved', (select count(*) from public.listing_reports where status = 'resolved'),
      'dismissed', (select count(*) from public.listing_reports where status = 'dismissed')),
    'shop', jsonb_build_object(
      'open', (select count(*) from public.shop_reports where status = 'open'),
      'reviewing', (select count(*) from public.shop_reports where status = 'reviewing'),
      'resolved', (select count(*) from public.shop_reports where status = 'resolved'),
      'dismissed', (select count(*) from public.shop_reports where status = 'dismissed'))
  );
end;
$$;
revoke all on function public.admin_report_counts() from public, anon;
grant execute on function public.admin_report_counts() to authenticated;

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
    'open_reports',
      (select count(*) from public.listing_reports where status in ('open', 'reviewing'))
      + (select count(*) from public.shop_reports where status in ('open', 'reviewing')),
    'orders', (select count(*) from public.orders),
    'products', (select count(*) from public.products)
  );
end;
$$;
