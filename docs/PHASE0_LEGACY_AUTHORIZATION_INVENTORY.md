# Legacy authorization quarantine plan

No legacy value may seed `seller_accounts`. Until broad enforcement is approved,
the following repository paths still treat legacy state as authorization or
trusted seller context:

- `private.is_seller()` checks `profiles.account_type = 'Seller'`.
- product update/delete, campaigns, LIVE, and blocked-user RLS call
  `private.is_seller()`.
- `create_product`, `update_seller_order`, `create_follower_campaign`,
  `toggle_shop_follow`, and live notification/session behavior still use
  `account_type`, `seller_verification`, or the legacy helper.
- `create_product` reads `seller_verification.status` and `listingLimit`.
- `review_seller_verification` copies `seller_tier`, `listing_limit`,
  school-verification fields, and profile `trust_score` into the public summary.
- trust-refresh and listing-expiry triggers use `trust_score`,
  `is_verified_seller`, `seller_tier`, and `verification_expiry`.

## Required pre-enforcement inventory

On a disposable local or staging database, identify:

1. every legacy Seller profile and its Auth linkage;
2. every application status, tier, limit, and review timestamp;
3. every profile verification/trust field and its provenance;
4. all outstanding order items by Seller;
5. reviewed Sellers approved for a new `seller_accounts` row;
6. exact outstanding orders requiring a temporary fulfillment grant.

Existing rows remain quarantined as historical information. Full seller access
requires a separately reviewed `seller_accounts` activation. Buyers retain all
Buyer capabilities even while an application is pending or rejected. Historical
orders, products, and messages are not deleted or rewritten.

No enforcement or data backfill is performed by this remediation.

