// Grants or revokes marketplace administrator access for an existing Auth user.
// Admins are never created through public registration; this trusted script is
// the only supported path. Run it from a secured operator machine.
//
//   node --env-file=.env provision-admin.mjs grant  admin@example.com "Ticket OPS-123"
//   node --env-file=.env provision-admin.mjs revoke admin@example.com "Left the team"
//   Add --apply to write; without it the script only reports what it would do.

import process from 'node:process';

import {createClient} from '@supabase/supabase-js';

const apply = process.argv.includes('--apply');
const [action, rawEmail, reason] = process.argv.slice(2).filter((arg) => arg !== '--apply');

if (!['grant', 'revoke'].includes(action) || !rawEmail || !reason?.trim()) {
  console.error('Usage: provision-admin.mjs grant|revoke <email> "<reason>" [--apply]');
  process.exit(1);
}
for (const name of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']) {
  if (!process.env[name]) throw new Error(`${name} is required.`);
}

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  {auth: {autoRefreshToken: false, persistSession: false}},
);

const email = rawEmail.trim().toLowerCase();
let user;
for (let page = 1; !user; page += 1) {
  const {data, error} = await supabase.auth.admin.listUsers({page, perPage: 1000});
  if (error) throw error;
  user = data.users.find((candidate) => candidate.email?.toLowerCase() === email);
  if (data.users.length < 1000) break;
}
if (!user) throw new Error(`No Auth user exists for ${email}. The person must sign up first.`);
if (!user.email_confirmed_at) throw new Error(`${email} has not confirmed their email address.`);

const {data: profile} = await supabase
  .from('profiles')
  .select('id')
  .eq('auth_user_id', user.id)
  .maybeSingle();

console.log(`${apply ? 'APPLY' : 'DRY RUN'}: ${action} admin for ${email} (${user.id}).`);
if (!apply) process.exit(0);

if (action === 'grant') {
  const {error} = await supabase.from('admin_users').upsert({
    auth_user_id: user.id,
    granted_by: `provision-admin.mjs: ${reason.trim()}`.slice(0, 200),
    granted_at: new Date().toISOString(),
    revoked_at: null,
  });
  if (error) throw error;
} else {
  const {error} = await supabase
    .from('admin_users')
    .update({revoked_at: new Date().toISOString()})
    .eq('auth_user_id', user.id)
    .is('revoked_at', null);
  if (error) throw error;
}

const {error: auditError} = await supabase.from('audit_logs').insert({
  actor_kind: 'service',
  action: action === 'grant' ? 'admin_granted' : 'admin_revoked',
  target_profile_id: profile?.id ?? null,
  details: {auth_user_id: user.id, reason: reason.trim()},
});
if (auditError) throw auditError;

console.log('Done.');
