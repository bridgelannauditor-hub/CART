-- Read-only inventory for a disposable local or staging database.
-- No result from this script constitutes approval or activation.

select
  p.id as profile_id,
  p.auth_user_id is not null as has_auth_identity,
  p.account_type,
  p.is_verified_seller,
  p.seller_tier,
  p.school_email_verified,
  p.verification_expiry,
  p.trust_score,
  p.seller_verification ->> 'status' as legacy_profile_status,
  p.seller_verification ->> 'level' as legacy_profile_level,
  p.seller_verification ->> 'listingLimit' as legacy_profile_listing_limit,
  a.status as legacy_application_status,
  a.level as legacy_application_level,
  a.listing_limit as legacy_application_listing_limit,
  a.seller_tier as legacy_application_tier,
  a.school_email_verified as legacy_school_email_verified,
  a.reviewed_at
from public.profiles p
left join public.seller_verification_applications a on a.profile_id = p.id
where p.account_type = 'Seller'
   or p.is_verified_seller
   or p.seller_verification is not null
   or a.profile_id is not null
order by p.id;

select
  oi.seller_id as profile_id,
  oi.order_id,
  array_agg(distinct oi.status order by oi.status) as seller_item_statuses,
  count(*) filter (
    where oi.status not in ('Delivered', 'Cancelled')
  ) as eligible_item_count
from public.order_items oi
group by oi.seller_id, oi.order_id
order by oi.order_id, oi.seller_id;

select profile_id, status, approved_by, approved_at, status_reason
from public.seller_accounts
order by profile_id;

select profile_id, order_id, granted_by, expires_at, revoked_at, reason
from public.seller_order_fulfillment_grants
order by order_id, profile_id;
