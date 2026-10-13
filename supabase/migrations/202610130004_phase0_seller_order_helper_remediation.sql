-- Phase 0 remediation: exact, seller-specific order-fulfillment authorization.
-- Existing seller RPCs do not call these helpers yet; broad enforcement remains
-- explicitly out of scope for this migration.

-- Keep arbitrary-profile activation checks service-only. Authenticated callers
-- may inspect only their own activation state through the no-argument overload.
revoke all on function private.has_active_seller_authorization(bigint)
  from public, anon, authenticated;
grant execute on function private.has_active_seller_authorization(bigint)
  to service_role;

create or replace function private.has_active_seller_authorization()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_active_seller_authorization(private.current_profile_id());
$$;

revoke all on function private.has_active_seller_authorization()
  from public, anon, authenticated;
grant execute on function private.has_active_seller_authorization()
  to authenticated, service_role;

create or replace function private.can_fulfill_seller_order(
  target_profile_id bigint,
  target_order_id bigint
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.orders o
    where o.id = target_order_id
      and target_profile_id = any(o.seller_ids)
      and exists (
        select 1
        from public.order_items oi
        where oi.order_id = o.id
          and oi.seller_id = target_profile_id
          and oi.status not in ('Delivered', 'Cancelled')
      )
      and (
        private.has_active_seller_authorization(target_profile_id)
        or exists (
          select 1
          from public.seller_order_fulfillment_grants g
          where g.profile_id = target_profile_id
            and g.order_id = o.id
            and g.revoked_at is null
            and g.expires_at > now()
        )
      )
  );
$$;

-- The generic predicate is for trusted backend use only.
revoke all on function private.can_fulfill_seller_order(bigint, bigint)
  from public, anon, authenticated;
grant execute on function private.can_fulfill_seller_order(bigint, bigint)
  to service_role;

-- Client-facing policies/RPCs use a caller-bound predicate and cannot select a
-- different seller profile ID.
create or replace function private.can_fulfill_seller_order(
  target_order_id bigint
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.can_fulfill_seller_order(
    private.current_profile_id(),
    target_order_id
  );
$$;

revoke all on function private.can_fulfill_seller_order(bigint)
  from public, anon, authenticated;
grant execute on function private.can_fulfill_seller_order(bigint)
  to authenticated, service_role;

