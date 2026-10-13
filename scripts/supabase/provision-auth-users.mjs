import {randomBytes} from 'node:crypto';
import process from 'node:process';

import {createClient} from '@supabase/supabase-js';

const apply = process.argv.includes('--apply');
for (const name of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']) {
  if (!process.env[name]) throw new Error(`${name} is required.`);
}

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  {auth: {autoRefreshToken: false, persistSession: false}},
);

const {data: profiles, error: profileError} = await supabase
  .from('profiles')
  .select('id,email,first_name,last_name,account_type,shop_name,profile_image')
  .is('auth_user_id', null)
  .order('id');
if (profileError) throw profileError;

const usersByEmail = new Map();
for (let page = 1; ; page += 1) {
  const {data, error} = await supabase.auth.admin.listUsers({page, perPage: 1000});
  if (error) throw error;
  for (const user of data.users) {
    if (user.email) usersByEmail.set(user.email.trim().toLowerCase(), user);
  }
  if (data.users.length < 1000) break;
}

const validProfiles = profiles.filter((profile) =>
  /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(profile.email?.trim() || ''),
);
console.log(`${apply ? 'APPLY' : 'DRY RUN'}: ${validProfiles.length} profile(s) need Supabase Auth identities.`);
if (!apply) {
  console.log(`${profiles.length - validProfiles.length} profile(s) have no valid email and would be skipped.`);
  process.exit(0);
}

let created = 0;
let linked = 0;
let skipped = profiles.length - validProfiles.length;

for (const profile of validProfiles) {
  const email = profile.email.trim().toLowerCase();
  let authUser = usersByEmail.get(email);

  if (!authUser) {
    const {data, error} = await supabase.auth.admin.createUser({
      email,
      password: randomBytes(48).toString('base64url'),
      email_confirm: true,
      user_metadata: {
        first_name: profile.first_name,
        last_name: profile.last_name,
        account_type: profile.account_type,
        shop_name: profile.shop_name,
        avatar_url: profile.profile_image,
        migrated_from_firebase: true,
      },
    });
    if (error) throw new Error(`Could not provision profile ${profile.id}: ${error.message}`);
    authUser = data.user;
    created += 1;
  }

  const {error: linkError} = await supabase
    .from('profiles')
    .update({auth_user_id: authUser.id})
    .eq('id', profile.id)
    .is('auth_user_id', null);
  if (linkError) throw new Error(`Could not link profile ${profile.id}: ${linkError.message}`);
  linked += 1;
}

console.log(`Created ${created} Auth user(s); linked ${linked} profile(s); skipped ${skipped}.`);
console.log('Existing customers must use Forgot Password once before their first Supabase login.');

