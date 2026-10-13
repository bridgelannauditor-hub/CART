import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, '..', '..');
const migrationPath = path.join(
  projectRoot,
  'supabase',
  'migrations',
  '202610130002_phase0_buyer_only_signup.sql',
);
const sql = fs.readFileSync(migrationPath, 'utf8');

const handlerMatch = sql.match(
  /create or replace function private\.handle_new_auth_user\(\)[\s\S]*?\n\$\$;/i,
);
assert.ok(handlerMatch, 'Buyer-only Auth trigger function must exist');
const handler = handlerMatch[0];

assert.match(handler, /'Customer'/, 'new profiles must be Buyers');
assert.match(handler, /insert into public\.profiles/i);
assert.match(handler, /coalesce\(new\.email, ''\)/i);
assert.doesNotMatch(handler, /requested_type/i);
assert.doesNotMatch(handler, /seller_verification_applications/i);
assert.doesNotMatch(handler, /migrated_from_firebase/i);
assert.doesNotMatch(handler, /->>\s*'account_type'/i);
assert.doesNotMatch(handler, /->\s*'seller_verification'/i);
assert.match(handler, /new\.email_confirmed_at is null/i);
assert.match(handler, /existing_profile\.auth_user_id <> new\.id/i);
assert.match(handler, /set auth_user_id = new\.id/i);
const authIdentityLookup = handler.indexOf('where auth_user_id = new.id');
const emailFallbackLookup = handler.indexOf(
  "where lower(email) = lower(coalesce(new.email, ''))",
);
assert.ok(authIdentityLookup >= 0, 'existing Auth identity lookup must exist');
assert.ok(emailFallbackLookup >= 0, 'confirmed-email fallback lookup must exist');
assert.ok(
  authIdentityLookup < emailFallbackLookup,
  'Auth identity lookup must run before email fallback to prevent duplicate profiles',
);

const craftedMetadata = [
  { account_type: 'Seller' },
  { account_type: 'Admin', role: 'Admin' },
  { role: 'moderator', reviewer: true, support: true },
  { seller_verification: { status: 'approved', isVerifiedSeller: true } },
  { seller_verification: { level: 'administrator', listingLimit: 999999 } },
  { account_type: ['Seller'], seller_verification: 'malformed' },
];
const privilegedKeys = [
  'account_type',
  'role',
  'admin',
  'moderator',
  'reviewer',
  'support',
  'seller_verification',
  'listingLimit',
  'trustScore',
  'isVerifiedSeller',
];
for (const metadata of craftedMetadata) {
  const serialized = JSON.stringify(metadata);
  for (const key of privilegedKeys) {
    if (serialized.includes(key)) {
      assert.doesNotMatch(
        handler,
        new RegExp(`raw_user_meta_data\\s*(?:->|->>)\\s*'${key}'`, 'i'),
        `handler must not consume privileged metadata key ${key}`,
      );
    }
  }
}

assert.match(sql, /drop trigger if exists zz_capture_extended_seller_application/i);
assert.match(sql, /drop trigger if exists zz_sync_confirmed_school_email/i);
assert.match(sql, /create trigger on_auth_user_created/i);
assert.match(sql, /create trigger on_auth_user_email_confirmed/i);
assert.match(sql, /function private\.sync_verified_auth_email/i);
assert.match(sql, /revoke update \([\s\S]*?email,[\s\S]*?account_type,[\s\S]*?seller_verification/);
assert.doesNotMatch(sql, /create or replace function private\.is_seller/i);
assert.doesNotMatch(sql, /insert\s+into\s+public\.seller_accounts/i);
assert.doesNotMatch(sql, /review_seller_verification/i);
assert.doesNotMatch(sql, /from service_role/i);

const applicationGrant = sql.match(
  /grant insert \(([\s\S]*?)\) on public\.seller_verification_applications to authenticated;/i,
);
assert.ok(applicationGrant, 'safe application column grant must exist');
for (const forbiddenColumn of [
  'status',
  'level',
  'listing_limit',
  'identity_capture_completed',
  'face_capture_completed',
  'school_email_verified',
  'seller_tier',
  'trust_score',
  'reviewed_at',
]) {
  assert.doesNotMatch(
    applicationGrant[1],
    new RegExp(`\\b${forbiddenColumn}\\b`, 'i'),
    `authenticated insert grant must exclude ${forbiddenColumn}`,
  );
}

console.log('Phase 0 signup migration static regression checks passed.');

