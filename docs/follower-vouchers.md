# Follower vouchers, version 1

Seller entry: Shop Management → Followers & Vouchers. Customer entry: Profile → My Vouchers.

Supports one current campaign per seller, percentage/fixed discounts, minimum seller subtotal, percentage cap, quantity, start/end dates and claim validity. Defaults: 10%, ₱500 minimum, ₱100 cap, seven days, 100 vouchers. Campaigns apply to the entire shop and first-time followers only. End the current campaign to create another; issued vouchers store a snapshot and survive campaign changes.

Firestore collections: `followerCampaigns` (seller ID), `shopFollowHistory` (customer/seller ID), `customerVouchers` (campaign/customer ID). Existing `shopFollows` remains the current follower list. Permanent history and deterministic claim IDs prevent repeat claims. Follow, history, quantity and claim commit in one transaction. Checkout commits redemption and the order together, rechecks product ownership/prices and stores separate seller discounts. Inventory updates continue using the existing order repository behavior.

Cancelling every item from an issuing seller restores its claim with its original expiry. Partial cancellations retain redemption and recalculate the discount against remaining seller items, including the minimum purchase. Restored expired claims appear under Expired. Cancelled voucher orders cannot be reopened because their claims may have been used on another order. Analytics display the current campaign's claims/redemptions and remaining net order revenue (not a delivered-payment metric).

## Deployment validation

No Firestore rules or emulator configuration is present in this workspace. The implementation follows the existing client-managed Firestore architecture. Before production, validate the deployed rules for all three new collections and order redemption updates. Server rules or trusted backend operations must enforce authenticated customer/seller ownership, immutable claim terms/history, campaign capacity, trusted time, and atomic redemption. Client transactions prevent normal concurrent duplication but do not defend against a modified client. Historical unfollows before this feature had no permanent record and cannot be reconstructed.

Use two customer sessions to test the last available claim and concurrent redemption. Verify an existing follower, unfollow/refollow, paused/ended/expired campaigns, claim expiry, two-seller checkout, partial seller cancellation, full seller cancellation, and a restored claim subsequently used by another order. New collection access failures should be checked against the deployed rules. No rules are deployed by this change.

Advanced targeting, issuance to existing followers, and milestones are deferred as requested for the first version.
