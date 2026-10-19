import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');

const migration = read(
  'supabase/migrations/202610150002_enforce_marketplace_authorization.sql',
);

assert.match(migration, /create view public\.marketplace_profiles/i);
assert.doesNotMatch(
  migration.match(/create view public\.marketplace_profiles[\s\S]*?from public\.profiles;/i)?.[0] ?? '',
  /\b(email|phone|auth_user_id|legacy_firebase_uid|seller_verification)\b/i,
);
assert.match(migration, /drop policy if exists profiles_read_authenticated/i);
assert.match(migration, /auth_user_id = \(select auth\.uid\(\)\)/i);
assert.match(
  migration,
  /private\.has_active_seller_authorization\(private\.current_profile_id\(\)\)/i,
);
assert.match(migration, /enforce_active_seller_product_insert/i);
assert.match(migration, /enforce_active_seller_order_item_insert/i);
assert.match(migration, /enforce_active_seller_fulfillment/i);
assert.match(migration, /revoke update \(is_live\)/i);
assert.match(migration, /create or replace function public\.set_my_live_status/i);
assert.match(migration, /revoke update \(shop_name, cover_image, profile_image\)/i);
assert.match(migration, /create or replace function public\.update_my_shop_profile/i);
assert.match(migration, /Conversation membership cannot be changed/i);
assert.match(migration, /Recipients may only mark messages as read/i);
assert.match(migration, /invalidate_changed_identity_evidence/i);
assert.match(migration, /new\.identity_status := 'not_started'/i);

const userRepository = read('lib/repositories/user_repository.dart');
assert.match(userRepository, /from\('marketplace_profiles'\)/);
assert.match(userRepository, /rpc\(\s*'update_my_shop_profile'/);
const shopRepository = read('lib/repositories/shop_repository.dart');
assert.match(shopRepository, /from\('marketplace_profiles'\)/);
assert.match(shopRepository, /rpc\(\s*'set_my_live_status'/);
const liveRepository = read('lib/repositories/live_repository.dart');
assert.match(liveRepository, /from\('marketplace_profiles'\)/);

console.log('Marketplace authorization static regression checks passed.');
