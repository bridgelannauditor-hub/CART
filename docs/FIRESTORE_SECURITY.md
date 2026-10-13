# Firestore security baseline

## Current state

The repository now contains a default-deny Firestore ruleset, callable commerce functions, declared composite indexes, and emulator tests. The rules scope data access through the authenticated Firebase UID and the numeric application user ID stored in that user's profile.

Protected areas include:

- user profiles and immutable identity fields
- profile email changes constrained to the verified email in the Firebase Auth token
- validated per-account notification preference maps
- seller-owned products
- customer- and seller-scoped order reads
- customer-owned reviews
- recipient-owned notifications
- participant-only conversations and messages
- seller-owned follower campaigns
- read-only customer/seller voucher access with server-owned claims and redemption
- follows, follow history, and shop visits
- seller-owned LIVE sessions, comments, and moderation
- a deny-all fallback for undeclared collections

## Trusted commerce operations

The `asia-southeast1` callable functions now own:

- authoritative product price, option, seller, and stock validation
- required delivery address and supported payment validation
- per-seller subtotal and voucher discount calculation
- atomic stock decrement, order creation, voucher redemption, and notifications
- customer line-item cancellation with stock and voucher restoration
- seller-specific fulfillment, tracking, and forward-only status transitions
- first-follow history, campaign quantity, and one-time follower voucher issuance
- delivered-order review eligibility and one review per customer/product pair
- concurrency-safe product rating totals, averages, and review counts
- collision-safe numeric user and product ID allocation based on both counters and existing records
- authenticated profile creation and seller-owned product creation with server-assigned identity fields
- recipient notification preferences for trusted order events

Direct client creation of profiles and products, all counter access, and direct creation or modification of orders, vouchers, follows, follow history, and reviews are denied. Product ownership and rating aggregates are also server-owned. Order and cancellation notifications are written in the same trusted transactions.

## Remaining production deployment gate

Review aggregation and numeric user/product allocation are now migrated. The current rules and functions are ready for a controlled staging deployment. Deploy the functions first, test the updated app build, and only then deploy the rules because older app builds still attempt the client writes that the new rules deny.

The 2026-10-07 deployment attempt to `cart11-fc0e9` stopped before uploading functions because the project is not on the Blaze plan. Cloud Functions deployment requires Cloud Build and Artifact Registry APIs that Firebase will not enable on the current plan. Rules and indexes were intentionally not deployed, preserving compatibility with the currently installed app. Upgrade the project or configure a separate staging Firebase project before retrying.

## Validation

Install and run the rule tests from the repository root:

```powershell
npm install --prefix firebase_rules_test
npm install --prefix functions
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
npx firebase-tools emulators:exec --only firestore --project craft-of-love-rules-test "npm test --prefix firebase_rules_test"
npx firebase-tools emulators:exec --only firestore --project craft-of-love-rules-test "npm test --prefix functions"
```

The final local emulator runs on 2026-10-07 passed:

- 14 Firestore authorization tests, including denial of unverified profile email changes and direct profile, product, counter, order, follower, voucher, and review mutations
- 16 trusted integration tests covering commerce, notification preferences, reviews, concurrent user/product ID allocation, idempotent profile creation, server-owned product identity and aggregates, and customer product-creation denial

For staging, deploy functions before tightening the rules:

```powershell
firebase deploy --only functions --project cart11-fc0e9
firebase deploy --only firestore:rules,firestore:indexes --project cart11-fc0e9
```

Deployment should be followed by a staging smoke test for registration, restored sessions, verified email changes, role-guarded navigation, product browsing, checkout, cancellation, vouchers, reviews, messaging, notifications, and LIVE controls.

## Local credential storage

Database version 17 rebuilds the local `users` table without its former password column. New database creation uses the credential-free schema, and the application user model cannot serialize a password. Sign-in, password reset, and password changes use Firebase Auth exclusively.
