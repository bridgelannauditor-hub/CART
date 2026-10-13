# C+ART Marketplace

C+ART is a Flutter marketplace for handmade products. Buyers can browse shops,
manage carts and favorites, claim vouchers, place multi-seller orders, chat,
and follow order progress. Seller-facing code supports product management,
promotions, fulfillment, analytics, chat, and LIVE shopping.

> **Security status:** Phase 0 containment is under review. The five Phase 0
> migrations are committed as source but have not been deployed or validated
> against a local, staging, or production Supabase database. Do not deploy them
> to production, activate Sellers, or enable LIVE hosting until the validation
> and rollout gates below have been completed.

## Technology

- Flutter and Dart
- Supabase Auth, PostgreSQL, RPCs, and Row Level Security
- Firebase Authentication, Cloud Firestore, Cloud Functions, and security rules
  retained by existing application paths during migration
- SQLite for local cache and offline state
- Cloudinary for product, profile, and chat media
- Agora SDK for LIVE video; production token issuance is not implemented

The application is being migrated incrementally. Existing Firebase, SQLite,
Cloudinary, and Agora functionality must not be removed merely because a
Supabase equivalent is being introduced.

## Account and authorization model

- Public registration always creates a Buyer (`Customer`) profile.
- A Buyer applies to sell from the same account.
- Client Auth metadata is not trusted for roles, Seller approval, identity
  verification, listing limits, trust scores, or administrative privileges.
- `public.seller_accounts` is the planned server-controlled source of active
  Seller authorization.
- Existing legacy Seller fields are historical input for manual review; they do
  not automatically create active `seller_accounts` records.
- Temporary fulfillment grants are limited to an exact Seller and exact order.
- Application approval, identity verification, shop approval, and active Seller
  authorization are separate states.

The current Phase 0 foundation deliberately does **not** replace every legacy
`private.is_seller()` check. Broad Seller enforcement requires a separate,
reviewed rollout after existing Sellers and outstanding orders are inventoried.

## Repository structure

```text
lib/                    Flutter application
test/                   Flutter unit and route-guard tests
functions/              Firebase Cloud Functions
firebase_rules_test/    Firestore authorization tests
supabase/migrations/    Ordered PostgreSQL migrations
supabase/phase0/        Read-only transition and security inventory queries
supabase/tests/         Disposable pgTAP authorization tests
scripts/security/       Source-level Phase 0 regression checks
scripts/supabase/       Trusted migration utilities and safe env example
docs/                   Architecture, audit, and feature documentation
```

## Local Flutter setup

1. Install a Flutter SDK compatible with `pubspec.lock`.
2. Run `flutter pub get`.
3. Configure the intended Firebase development project. Confirm that
   `android/app/google-services.json`, package identifiers, OAuth providers, and
   signing fingerprints all refer to that environment.
4. Provide only the public Supabase client configuration through Dart defines:

   ```sh
   flutter run \
     --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
     --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
   ```

5. Configure Cloudinary with a restricted unsigned upload preset that enforces
   the same file types and size limits as the client.
6. Run the application with `flutter run`.

Never place a Supabase service-role key, identity-provider secret, Cloudinary
API secret, or production Agora token in Flutter source or `--dart-define`.
Server-only scripts may use a local ignored file based on
[`scripts/supabase/.env.example`](scripts/supabase/.env.example).

## Phase 0 migrations

The migrations must be reviewed and applied in this order:

1. `202610130001_phase0_seller_authorization_foundation.sql`
2. `202610130002_phase0_buyer_only_signup.sql`
3. `202610130003_phase0_safe_profile_linking.sql`
4. `202610130004_phase0_seller_order_helper_remediation.sql`
5. `202610130005_phase0_seller_application_rpc.sql`

They add the Seller authorization foundation, enforce Buyer-only public signup,
protect profile linking, bind order-helper calls to the authenticated Seller,
and provide a caller-bound Seller application RPC.

Historical migrations must not be rewritten. No existing Seller is activated
or backfilled by these five migrations.

## Disposable Supabase validation

Database testing must use a disposable local Supabase project. Do not use a
production connection string, production access token, or a dump containing
real identity, payment, message, address, or order data.

Prerequisites:

- Docker Desktop with its WSL 2 backend on Windows
- A pinned Supabase CLI
- A local `supabase/config.toml` generated with `supabase init`

Run:

```sh
supabase start
supabase db reset
supabase test db supabase/tests/phase0_prevalidation.sql
supabase stop --no-backup
```

The pgTAP suite uses the real PostgreSQL `authenticated` and `service_role`
roles, local JWT claims, and transactionally rolled-back fixtures. It tests
forged signup metadata, profile linking conflicts, application field ownership,
Buyer and inactive-Seller denials, message/profile privacy boundaries,
exact-order grants, multi-seller orders, and service-role access.

Several denial tests intentionally expose known controls that are not yet
implemented. Those failures are release blockers, not tests to skip or mark as
passing. See [`supabase/tests/PHASE0_VALIDATION.md`](supabase/tests/PHASE0_VALIDATION.md)
for the full procedure.

## Flutter and source verification

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
node --check scripts/security/check_phase0_signup_migration.mjs
node scripts/security/check_phase0_signup_migration.mjs
node --check scripts/security/check_phase0_remediation.mjs
node scripts/security/check_phase0_remediation.mjs
```

Static scripts verify expected source patterns only. They do not prove that a
migration executes, an RLS policy denies an operation, or a deployed database
matches the repository.

## Known release blockers

The current source still requires separately reviewed containment work for:

- active-Seller checks in product, campaign, fulfillment, and LIVE operations;
- message-content edits, read-state updates, deletion, and conversation
  membership changes;
- public-safe profile views and private profile RLS;
- COD-only checkout enforcement until other payment integrations exist;
- idempotent checkout requests;
- session-specific, server-issued Agora tokens and safe LIVE session selection;
- trusted, immutable Seller approval evidence tied to a reviewer and application
  revision;
- cloud synchronization for customer data that is still local-only.

Agora LIVE hosting must remain disabled for production. A temporary token or
shared test channel is not a production credential design.

## Deployment and rollout gates

Before any Phase 0 production deployment:

1. Apply all historical and Phase 0 migrations to a clean disposable project.
2. Run the complete pgTAP suite and investigate every failure.
3. Repeat against a sanitized representative pre-Phase-0 schema.
4. Run the read-only Seller and outstanding-order inventories in
   `supabase/phase0/`.
5. Review the exact Seller activation list manually. Never infer activation
   from legacy account type or verification fields.
6. Create any transitional fulfillment grants only for reviewed outstanding
   orders, with expiry and revocation support.
7. Update clients before enabling stricter RLS or RPC enforcement.
8. Prepare rollback steps and obtain explicit production-deployment approval.

Do not run destructive validation against production data.

## Documentation

- [Application audit](docs/APP_AUDIT_2026-10-07.md)
- [Phase 0 authorization foundation](docs/PHASE0_FOUNDATION.md)
- [Legacy authorization quarantine](docs/PHASE0_LEGACY_AUTHORIZATION_INVENTORY.md)
- [Supabase migration guide](docs/SUPABASE_MIGRATION.md)
- [Follower vouchers](docs/follower-vouchers.md)
- [LIVE shopping](docs/live-shopping.md)
- [Firestore security](docs/FIRESTORE_SECURITY.md)

The preserved pre-Phase-0 Git baseline is commit
`fa8dd2c038c68b020cdc5a58b993782936b1140a`. The external backup archive is
intentionally not stored in this repository.
