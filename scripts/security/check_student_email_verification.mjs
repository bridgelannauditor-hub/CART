import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(
  'supabase/migrations/202610150003_student_school_email_verification.sql',
  'utf8',
);
const requestFunction = readFileSync(
  'supabase/functions/request-school-email-verification/index.ts',
  'utf8',
);
const verifyFunction = readFileSync(
  'supabase/functions/verify-school-email-code/index.ts',
  'utf8',
);

assert.match(migration, /application_revision integer not null/);
assert.match(migration, /school_email text not null/);
assert.match(migration, /attempts between 0 and 5/);
assert.match(migration, /created_at > now\(\) - interval '60 seconds'/);
assert.match(migration, /application\.revision <> challenge\.application_revision/);
assert.match(migration, /lower\(application\.school_email\) <> challenge\.school_email/);
assert.match(migration, /school_email_verified = true/);
assert.match(migration, /to service_role/);
assert.match(
  migration,
  /revoke all on function public\.service_create_school_email_challenge[\s\S]*?from public, anon, authenticated;/,
);
assert.match(
  migration,
  /revoke all on function public\.service_verify_school_email_challenge[\s\S]*?from public, anon, authenticated;/,
);

assert.match(requestFunction, /crypto\.getRandomValues/);
assert.match(requestFunction, /hashSchoolEmailCode/);
assert.match(requestFunction, /api\.resend\.com\/emails/);
assert.match(verifyFunction, /service_verify_school_email_challenge/);
assert.match(verifyFunction, /\^\\d\{6\}\$/);

console.log('Student school-email verification static checks passed.');
