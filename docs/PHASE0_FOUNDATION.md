# Phase 0 seller authorization foundation

## Baseline

- Pre-change Git commit: `fa8dd2c038c68b020cdc5a58b993782936b1140a`
- The external backup archive and its SHA-256 are reported separately; the
  archive is intentionally outside the repository.
- Historical migrations through
  `202610120002_buyer_signup_profile_link.sql` remain unchanged.

## Migration dependency review

`202610130001_phase0_seller_authorization_foundation.sql` depends on:

- `public.profiles` and `public.orders` from the initial marketplace migration;
- `private.set_updated_at()` from the initial marketplace migration;
- `auth.users`, `authenticated`, and `service_role` from Supabase Auth;
- `profiles.is_verified_seller`, which was added by
  `202610110009_seller_trust_and_verification.sql`, only in the separate
  read-only inventory script.

The migration adds authorization state but does not yet change
`private.is_seller()`, seller RPCs, grants, or RLS policies. Applying this
foundation alone therefore does not activate, deactivate, approve, or block any
existing account.

## Trust boundary

Only a trusted service-role/admin process may write either foundation table.
There are no authenticated or anonymous table policies or grants.

An active seller row requires both an approving Auth user and an approval
timestamp. No account is backfilled from `account_type`, application status,
`seller_verification`, or `is_verified_seller`.

The order-transition table is limited to an exact `(profile_id, order_id)` pair,
must expire, may be revoked, and is effective only while the seller belongs to
the order and the order is not delivered or cancelled. Later enforcement may
consult it only from the seller-order fulfillment RPC.

## Deployment gate

Before the enforcement migration is applied to any environment:

1. Run `supabase/phase0/inspect_seller_transition.sql` on staging/local.
2. Review sellers and outstanding orders manually.
3. Insert approved `seller_accounts` and any necessary exact-order transition
   grants through a trusted service-role/admin process.
4. Test Buyer, inactive Seller, active Seller, transition-granted Seller,
   unrelated authenticated user, and service-role behavior.

No migration in this repository has been deployed by this implementation work.
