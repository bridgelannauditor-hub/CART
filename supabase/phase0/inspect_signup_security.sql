-- Read-only post-migration inspection for a local or staging Supabase database.
-- This verifies definitions, not runtime authorization behavior.

select
  t.tgname as trigger_name,
  pg_get_triggerdef(t.oid, true) as trigger_definition
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'auth'
  and c.relname = 'users'
  and not t.tgisinternal
order by t.tgname;

select
  n.nspname as function_schema,
  p.proname as function_name,
  pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'private'
  and p.proname in (
    'handle_new_auth_user',
    'capture_extended_seller_application',
    'sync_confirmed_school_email',
    'sync_verified_auth_email',
    'is_seller'
  )
order by p.proname;

select grantee, privilege_type, column_name
from information_schema.column_privileges
where table_schema = 'public'
  and table_name in ('profiles', 'seller_verification_applications')
  and grantee in ('anon', 'authenticated')
order by table_name, grantee, privilege_type, column_name;

