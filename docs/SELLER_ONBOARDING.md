# Users, registration, and Seller onboarding

## Roles

| Role | How the account gets it | What it can do |
| --- | --- | --- |
| **Buyer / Customer** | Public registration (email/phone + password with verification, or Google/Facebook). Always the default. | Browse, search, filter; cart and orders; delivery addresses; chat and watch LIVE; reviews and ratings; apply to sell. |
| **Seller** | Only through `admin_review_seller_application` after identity verification and shop review. Never by changing a role field. | Shop profile and listings; inventory, orders, reservations; customer chat and LIVE; sales reports and analytics. |
| **Admin** | Only through `scripts/supabase/provision-admin.mjs`, run by a trusted operator with the service-role key. Never through signup. | Verify Seller applications and shops; manage accounts; review reports and disputes; vouchers and campaigns; monitoring. |

A Seller is not an Admin, and a Buyer cannot become a Seller by editing
`profiles.account_type`. Authenticated clients have no `UPDATE` grant on that
column, on any `seller_verification_applications` column, or on
`seller_accounts`/`admin_users`. Every decision is made in Postgres functions
and enforced with RLS.

## How Seller legitimacy is validated

1. **Create a Buyer account.** Email/phone must be confirmed (Google/Facebook
   accounts already are). `submit_seller_application` refuses unconfirmed
   accounts.
2. **Apply.** The applicant fills in the existing application form and accepts
   the current Seller terms (`terms_version`, currently `2026-10`).
3. **Verify identity.** Flutter calls the `create-verification-session` Edge
   Function. The applicant captures the front and back of their ID with the
   camera, then completes a live selfie/liveness check and face match. All of
   this happens in the provider's hosted flow, so Cart never receives the images.
4. **Validate the result.** The provider calls the `verification-webhook` Edge
   Function. Its signature and timestamp are verified before the result is
   recorded with `service_record_verification_result`.
5. **Shop setup.** This is only possible once identity is `verified`
   (`save_shop_draft`). It covers the shop name, main craft, description, and
   city.
6. **Final approval.** An admin approves with
   `admin_review_seller_application`. Approval requires accepted terms, verified
   identity, and a submitted shop. It is tied to the application revision the
   admin reviewed, and admins cannot approve themselves. Approval creates the
   active `seller_accounts` row.

### What Cart validates

| Area | What is checked | Who checks it |
| --- | --- | --- |
| Account ownership | Confirmed email/phone, authenticated session | Supabase Auth |
| Identity | ID details and document validity | Verification provider |
| Liveness | Selfie is a live person | Verification provider |
| Face match | Selfie matches the ID portrait | Verification provider |
| Personal details | Consistency of submitted details | Backend + provider |
| Shop legitimacy | Shop info, prohibited items, policy compliance | Backend + admin review |
| Payout details | Meets the payment provider's requirements | Payment provider (not yet integrated) |

A valid ID does not prove that a shop is trustworthy, so identity
verification and shop approval are separate states (`identity_status` and
`shop_status`).

### When verification fails

| Outcome | What happens |
| --- | --- |
| **Verified** | The applicant may set up a shop. Seller permissions stay off until final approval. |
| **Needs another attempt** | Unclear image, failed capture, or interrupted session. Up to 3 attempts. A provider outage uses no attempt. |
| **Under review** | The provider was not confident, or all 3 attempts were used. An admin resolves it with `admin_resolve_identity_review`. Nothing is activated meanwhile. |
| **Rejected** | The application closes. The applicant sees a plain-language reason (`describeSellerReasonCode`), never raw provider data, and may appeal up to 2 times (`appeal_seller_application`). An admin can reopen the case with `request_changes`, which also grants fresh identity attempts. |

## Records

| Record | Purpose |
| --- | --- |
| `profiles` | General account and customer information |
| `seller_verification_applications` | Application, terms, identity status, shop draft, review, appeals (the "seller_applications" record) |
| `verification_sessions` | Provider reference, session status, pass/fail check flags, timestamps |
| `seller_accounts` | Approved Seller status (Phase 0 table) |
| `audit_logs` | Append-only log of verification and approval actions; readable by admins only |
| `admin_users` | Provisioned administrators; revocable |

Identity evidence stays with the provider. `verification_sessions.checks` keeps
only boolean flags (`document`, `liveness`, `face_match`, `personal_details`);
any other provider fields are dropped. Set the provider's retention period
to the shortest your compliance requirements allow, and delete evidence when
the application closes.

## What an applicant can do before approval

| Feature | Before Seller approval |
| --- | --- |
| Browse and buy products | Allowed |
| Apply to become a Seller | Allowed |
| Complete identity verification | Allowed |
| Prepare a shop draft | Allowed after successful identity verification |
| Publish products for sale | Not allowed* |
| Accept and fulfil marketplace orders as a Seller | Not allowed* |
| Start LIVE selling | Not allowed* |
| Access Seller payouts | Not allowed (payouts not built yet) |

\* These are enforced by `supabase/rollout/enforce_active_seller.sql`. It is
staged on purpose rather than added as a migration, because legacy Sellers
must first be reviewed and given `seller_accounts` rows (see the README
rollout gates). Until it is applied, the legacy `account_type` checks still
apply, and only new applicants go through this flow.

## Setup

### Edge Functions

```sh
supabase functions deploy create-verification-session
supabase functions deploy verification-webhook --no-verify-jwt
supabase secrets set VERIFICATION_PROVIDER=http \
  VERIFICATION_API_URL=https://provider.example/api \
  VERIFICATION_API_KEY=... \
  VERIFICATION_WEBHOOK_SECRET=... \
  VERIFICATION_WEBHOOK_URL=https://<ref>.supabase.co/functions/v1/verification-webhook
```

`supabase/functions/_shared/verification_provider.ts` contains a generic HTTPS
adapter. Fit it to the chosen vendor's documented session API and webhook
signature, since each vendor differs. For local development only, set
`VERIFICATION_PROVIDER=mock` and `ALLOW_MOCK_VERIFICATION=true`, then send
outcomes with:

```sh
cd scripts/supabase
npm run simulate-verification -- <provider_session_id> verified
```

### Admins

```sh
cd scripts/supabase
npm run admin-dry-run -- grant admin@example.com "Ticket OPS-123"
npm run admin-apply -- grant admin@example.com "Ticket OPS-123"
npm run admin-apply -- revoke admin@example.com "Left the team"
```

The person must already have a confirmed account. Every grant and revocation
is written to `audit_logs`. Admins see an "Admin: Seller Applications" entry on
their profile screen, and the server re-checks admin access on every call.
Supabase MFA for admin accounts is strongly recommended.

## Tests

```sh
supabase test db supabase/tests/seller_onboarding_flow.sql
flutter test test/seller_onboarding_model_test.dart
```
