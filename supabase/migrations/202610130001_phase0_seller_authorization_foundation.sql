-- Phase 0 foundation: trusted seller authorization and narrow legacy-order access.
--
-- This migration is intentionally non-enforcing. Existing policies and RPCs keep
-- their current behavior until a later enforcement migration is reviewed and the
-- Flutter client is ready. No existing seller is activated or backfilled here.

create table public.seller_accounts (
  profile_id bigint primary key references public.profiles(id) on delete cascade,
  status text not null default 'inactive'
    check (status in ('inactive', 'active', 'suspended', 'revoked')),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  status_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint active_seller_has_approval check (
    status <> 'active' or (approved_by is not null and approved_at is not null)
  )
);

comment on table public.seller_accounts is
  'Server-controlled source of seller authorization. Never populate from client metadata or legacy seller flags.';

create trigger seller_accounts_set_updated_at
before update on public.seller_accounts
for each row execute function private.set_updated_at();

alter table public.seller_accounts enable row level security;
revoke all on table public.seller_accounts from public, anon, authenticated;
grant all on table public.seller_accounts to service_role;

create table public.seller_order_fulfillment_grants (
  profile_id bigint not null references public.profiles(id) on delete cascade,
  order_id bigint not null references public.orders(id) on delete cascade,
  granted_by uuid not null references auth.users(id) on delete restrict,
  reason text not null check (char_length(trim(reason)) between 1 and 500),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (profile_id, order_id),
  constraint fulfillment_grant_future_expiry check (expires_at > created_at),
  constraint fulfillment_grant_revocation_order check (
    revoked_at is null or revoked_at >= created_at
  )
);

comment on table public.seller_order_fulfillment_grants is
  'Manually reviewed, exact-order transition grants. These grants must never authorize products, promotions, shop approval, or LIVE.';

create trigger seller_order_fulfillment_grants_set_updated_at
before update on public.seller_order_fulfillment_grants
for each row execute function private.set_updated_at();

alter table public.seller_order_fulfillment_grants enable row level security;
revoke all on table public.seller_order_fulfillment_grants from public, anon, authenticated;
grant all on table public.seller_order_fulfillment_grants to service_role;

create or replace function private.has_active_seller_authorization(
  target_profile_id bigint
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.seller_accounts sa
    join public.profiles p on p.id = sa.profile_id
    where sa.profile_id = target_profile_id
      and sa.status = 'active'
      and p.account_type = 'Seller'
  );
$$;

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
  select
    private.has_active_seller_authorization(target_profile_id)
    or exists (
      select 1
      from public.seller_order_fulfillment_grants g
      join public.orders o on o.id = g.order_id
      where g.profile_id = target_profile_id
        and g.order_id = target_order_id
        and target_profile_id = any(o.seller_ids)
        and g.revoked_at is null
        and g.expires_at > now()
        and o.status not in ('Delivered', 'Cancelled')
    );
$$;

revoke all on function private.has_active_seller_authorization(bigint)
  from public, anon, authenticated;
revoke all on function private.can_fulfill_seller_order(bigint, bigint)
  from public, anon, authenticated;
grant execute on function private.has_active_seller_authorization(bigint)
  to authenticated, service_role;
grant execute on function private.can_fulfill_seller_order(bigint, bigint)
  to authenticated, service_role;

