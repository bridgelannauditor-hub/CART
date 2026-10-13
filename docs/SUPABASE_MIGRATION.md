# Firebase to Supabase migration

The Firebase-to-Supabase cutover was completed on 2026-10-11. Firebase source
data remains available as a rollback copy, but the Flutter app no longer
initializes Firebase or includes FlutterFire packages.

## What is ready

- `supabase/migrations/202610100001_initial_marketplace.sql` defines the
  PostgreSQL schema, constraints, indexes, Row Level Security policies, a new
  Auth profile trigger, and the seller-only `create_product` RPC.
- `scripts/supabase/migrate-firestore.mjs` copies the main Firestore datasets
  while preserving the existing numeric user, product, and order IDs.
- The migration tool is dry-run by default. It writes only when `--apply` is
  supplied.
- Migrations `202610100002` through `202610110008` add Auth linking, client
  grants, secure notification/chat/voucher/order/live RPCs, and Realtime.
- All nine migrated profiles are linked to Supabase Auth. Existing customers
  must use **Forgot password** once before their first Supabase password login.
- Flutter authentication, products, profiles, search, reviews, shops,
  notifications, chat, vouchers, orders, tracking, settings, and live selling
  now use Supabase.

The central script migrated Firestore. Device-local SQLite rows (cart,
favorites, delivery addresses, and settings) are not present in Firebase and
cannot be collected centrally. Existing device-local rows remain local until
an optional per-device synchronization feature is implemented.

## 1. Create the Supabase project

1. Sign in at <https://supabase.com/dashboard> and create a project.
2. Choose the region nearest the majority of customers.
3. Save the generated database password in a password manager.
4. In **Project Settings -> API** (or the project's **Connect** panel), copy:
   - Project URL
   - Publishable key (safe for the Flutter client when RLS is enabled)
   - Service-role key (server-only; never put this in Flutter or Git)
5. In **Authentication -> URL Configuration**, set the production Site URL and
   approved redirect URLs before enabling password recovery or social login.

The Flutter build-time configuration is kept in the ignored
`supabase.env.json`. Run Flutter with:

```powershell
flutter run --dart-define-from-file=supabase.env.json
```

For real customers, review the current Supabase plan limits, backups, support,
and availability requirements. A free project is useful for staging but should
not be treated as the production capacity plan without that review.

## 2. Apply the schema

For the first setup, open **SQL Editor -> New query**, paste the entire contents
of `supabase/migrations/202610100001_initial_marketplace.sql`, and run it.

For ongoing development, install the Supabase CLI and use versioned migrations:

```powershell
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Do not temporarily disable RLS to make the Flutter client work. Fix the policy
or RPC instead.

## 3. Obtain Firebase migration credentials

The migration script needs a Firebase service-account JSON file for the source
project. In Google Cloud Console:

1. Open project `cart11-fc0e9`.
2. Go to **IAM & Admin -> Service Accounts**.
3. Create a short-lived migration service account with read access to
   Firestore and Firebase Authentication only if Auth export is later required.
4. Download its JSON key outside the repository.
5. Revoke/delete the key after the migration is complete.

Never send the JSON key, database password, or Supabase service-role key in a
chat or commit them to the repository.

## 4. Install and dry-run the data migration

Open a new PowerShell window in the repository:

```powershell
cd scripts\supabase
npm install
Copy-Item .env.example .env
# Open .env locally and fill FIREBASE_PROJECT_ID and FIREBASE_SERVICE_ACCOUNT.
npm run dry-run
```

The dry run reads Firestore and prints the record count for each destination
table. It does not need or accept a Supabase service-role key.

Review the counts and any skipped records. Then provide the destination values
only in the local terminal and run the copy:

```powershell
# Add SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY to the ignored local .env.
npm run migrate
```

The importer uses idempotent upserts, so an interrupted copy can be rerun. Do
not edit source data during the final copy window.

## 5. Authentication migration

Firestore profiles are copied with their numeric IDs and
`legacy_firebase_uid`, but Firebase password hashes are not stored in Firestore.
The initial data script therefore does not create Supabase Auth users.

Recommended production transition:

1. Configure email/password, Google, and Facebook providers in Supabase Auth.
2. Import verified identities only through a reviewed server-side script.
3. Link each new `auth.users.id` to `profiles.auth_user_id` by verified email.
4. Require existing password users to use **Forgot password** on first Supabase
   login unless password hashes are exported and migrated through a separately
   tested supported process.
5. Test account linking carefully so a social provider cannot claim another
   user's profile by presenting an unverified email.

## 6. Validation queries

Run these in the Supabase SQL Editor after import:

```sql
select 'profiles' as table_name, count(*) from public.profiles
union all select 'products', count(*) from public.products
union all select 'orders', count(*) from public.orders
union all select 'order_items', count(*) from public.order_items
union all select 'reviews', count(*) from public.reviews;

select p.id
from public.products p
left join public.profiles s on s.id = p.seller_id
where s.id is null;

select oi.id
from public.order_items oi
left join public.orders o on o.id = oi.order_id
left join public.products p on p.id = oi.product_id
where o.id is null or p.id is null;
```

Both orphan checks must return zero rows.

## 7. Completed cutover

The schema, data copy, Auth provisioning, Flutter repository cutover, secure
RPCs, and Realtime publications are applied. Before a public release, complete
the production tests below, configure custom SMTP for password recovery, and
test the final Android/iOS builds with `supabase.env.json`.

## Required production tests

- A seller cannot create a product for another seller.
- A seller cannot edit rating, review count, or total sold.
- A customer cannot choose the checkout price or discount.
- Stock cannot become negative under concurrent purchases.
- A customer can only review a product delivered to that customer.
- A seller can only update their items inside a multi-seller order.
- Customers cannot read another customer's orders, addresses, vouchers, cart,
  notifications, or private messages.
- The publishable key works from Flutter; the service-role key is absent from
  the built application and source control.
