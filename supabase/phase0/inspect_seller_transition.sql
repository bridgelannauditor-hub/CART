-- Read-only inventory for staging/local review before Phase 0 enforcement.
-- Run only through a trusted SQL session. This script changes no data.

-- Seller candidates and the legacy fields that require human review.
select
  p.id as profile_id,
  p.shop_name,
  p.created_at as profile_created_at,
  p.is_verified_seller,
  a.status as legacy_application_status,
  a.level as legacy_application_level,
  a.submitted_at,
  a.reviewed_at
from public.profiles p
left join public.seller_verification_applications a on a.profile_id = p.id
where p.account_type = 'Seller'
order by p.id;

-- Outstanding order work by seller. Each row must be reviewed before an exact
-- transitional grant is inserted. No result from this query is auto-approved.
select
  oi.seller_id as profile_id,
  o.id as order_id,
  o.created_at as order_created_at,
  o.status as aggregate_order_status,
  array_agg(distinct oi.status order by oi.status) as seller_item_statuses,
  count(*) as seller_item_count
from public.orders o
join public.order_items oi on oi.order_id = o.id
where oi.status not in ('Delivered', 'Cancelled')
group by oi.seller_id, o.id, o.created_at, o.status
order by o.created_at, o.id, oi.seller_id;

-- Foundation state. An empty result is expected immediately after migration.
select profile_id, status, approved_by, approved_at, status_reason
from public.seller_accounts
order by profile_id;

select profile_id, order_id, granted_by, reason, expires_at, revoked_at
from public.seller_order_fulfillment_grants
order by order_id, profile_id;

