import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');

const linking = read('supabase/migrations/202610130003_phase0_safe_profile_linking.sql');
assert.match(linking, /Email registration is required/i);
assert.match(linking, /existing_profile\.account_type <> 'Customer'/i);
assert.match(linking, /for update/i);
assert.match(linking, /auth_user_id = new\.id/i);
assert.match(linking, /and account_type = 'Customer'/i);
assert.doesNotMatch(linking, /set\s+account_type\s*=/i);
assert.doesNotMatch(linking, /insert\s+into\s+public\.seller_accounts/i);

const expectedLinkDecision = ({
  linkedAuthId = null,
  authId,
  accountType,
  confirmed,
}) => {
  if (linkedAuthId === authId) return confirmed ? 'keep-and-sync' : 'keep';
  if (linkedAuthId !== null) return 'reject-duplicate';
  if (accountType !== 'Customer') return 'trusted-recovery-required';
  return confirmed ? 'link-buyer' : 'wait-for-confirmation';
};
assert.equal(
  expectedLinkDecision({authId: 'a', accountType: 'Customer', confirmed: true}),
  'link-buyer',
);
assert.equal(
  expectedLinkDecision({authId: 'a', accountType: 'Seller', confirmed: true}),
  'trusted-recovery-required',
);
assert.equal(
  expectedLinkDecision({
    linkedAuthId: 'a',
    authId: 'a',
    accountType: 'Customer',
    confirmed: true,
  }),
  'keep-and-sync',
);
assert.equal(
  expectedLinkDecision({
    linkedAuthId: 'other',
    authId: 'a',
    accountType: 'Customer',
    confirmed: true,
  }),
  'reject-duplicate',
);

const orderHelper = read(
  'supabase/migrations/202610130004_phase0_seller_order_helper_remediation.sql',
);
assert.match(
  orderHelper,
  /grant execute on function private\.has_active_seller_authorization\(bigint\)[\s\S]*?to service_role/i,
);
assert.match(
  orderHelper,
  /private\.has_active_seller_authorization\(private\.current_profile_id\(\)\)/i,
);
assert.match(orderHelper, /target_profile_id = any\(o\.seller_ids\)/i);
assert.match(orderHelper, /oi\.seller_id = target_profile_id/i);
assert.match(orderHelper, /oi\.status not in \('Delivered', 'Cancelled'\)/i);
assert.match(orderHelper, /g\.profile_id = target_profile_id/i);
assert.match(orderHelper, /g\.order_id = o\.id/i);
assert.match(orderHelper, /g\.revoked_at is null/i);
assert.match(orderHelper, /g\.expires_at > now\(\)/i);
assert.match(orderHelper, /private\.current_profile_id\(\)/i);
assert.match(
  orderHelper,
  /grant execute on function private\.can_fulfill_seller_order\(bigint, bigint\)[\s\S]*?to service_role/i,
);

const expectedFulfillment = ({belongs, statuses, active, grant}) =>
  belongs &&
  statuses.some((status) => !['Delivered', 'Cancelled'].includes(status)) &&
  (active || (grant?.exact && !grant.expired && !grant.revoked));
assert.equal(expectedFulfillment({belongs: false, statuses: ['Pending'], active: true}), false);
assert.equal(expectedFulfillment({belongs: true, statuses: ['Pending'], active: true}), true);
assert.equal(
  expectedFulfillment({
    belongs: true,
    statuses: ['Pending'],
    active: false,
    grant: {exact: false, expired: false, revoked: false},
  }),
  false,
);
assert.equal(
  expectedFulfillment({
    belongs: true,
    statuses: ['Pending'],
    active: false,
    grant: {exact: true, expired: true, revoked: false},
  }),
  false,
);
assert.equal(
  expectedFulfillment({
    belongs: true,
    statuses: ['Pending'],
    active: false,
    grant: {exact: true, expired: false, revoked: true},
  }),
  false,
);
assert.equal(expectedFulfillment({belongs: true, statuses: ['Delivered'], active: true}), false);
assert.equal(expectedFulfillment({belongs: true, statuses: ['Cancelled'], active: true}), false);
assert.equal(
  expectedFulfillment({belongs: true, statuses: ['Delivered', 'Pending'], active: true}),
  true,
);

const application = read(
  'supabase/migrations/202610130005_phase0_seller_application_rpc.sql',
);
assert.match(application, /private\.current_profile_id\(\)/i);
assert.match(application, /status = 'under_review'/i);
assert.match(application, /seller_tier = excluded\.seller_tier/i);
assert.match(application, /school_email_verified = false/i);
assert.match(application, /identity_capture_completed = false/i);
assert.match(application, /face_capture_completed = false/i);
assert.match(application, /listing_limit = 5/i);
assert.doesNotMatch(application, /payload\s*->>\s*'(status|level|listingLimit|trustScore|sellerTier)'/i);
assert.match(application, /grant execute[\s\S]*to authenticated, service_role/i);

const authService = read('lib/services/auth_service.dart');
assert.match(authService, /'account_type': 'Customer'/);
assert.doesNotMatch(authService, /'seller_verification':/);
const accountTypeScreen = read('lib/screens/auth/account_type_screen.dart');
assert.match(accountTypeScreen, /CREATE ACCOUNT TO APPLY/);
assert.doesNotMatch(accountTypeScreen, /_continue\(context, 'Seller'\)/);
const registerScreen = read('lib/screens/auth/register_screen.dart');
assert.doesNotMatch(registerScreen, /Application submitted\. Confirm your email/);

console.log('Phase 0 remediation static regression checks passed.');
