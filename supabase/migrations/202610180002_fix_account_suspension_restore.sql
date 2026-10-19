-- Restoring a suspended account failed with "column reference "reason" is
-- ambiguous": account_suspensions has a reason column, and so does the
-- function's reason parameter. Qualify the parameter in the update.

create or replace function public.admin_set_account_suspension(
  target_profile_id bigint,
  suspend boolean,
  reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_row public.profiles;
  seller_status text;
  clean_reason text := trim(coalesce(admin_set_account_suspension.reason, ''));
begin
  perform private.require_admin();
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason is required.' using errcode = '22023';
  end if;
  if target_profile_id = private.current_profile_id() then
    raise exception 'Administrators cannot suspend their own account.' using errcode = '42501';
  end if;
  select * into profile_row from public.profiles where id = target_profile_id;
  if not found then
    raise exception 'Account not found.' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from public.admin_users a
    where a.auth_user_id = profile_row.auth_user_id and a.revoked_at is null
  ) then
    raise exception 'Administrator accounts cannot be suspended.' using errcode = '42501';
  end if;

  if suspend then
    if private.is_suspended(target_profile_id) then
      raise exception 'This account is already suspended.' using errcode = '23514';
    end if;
    insert into public.account_suspensions (profile_id, reason, suspended_by)
    values (target_profile_id, clean_reason, (select auth.uid()));
  else
    update public.account_suspensions
    set lifted_at = now(), lifted_by = (select auth.uid()), lift_reason = clean_reason
    where profile_id = target_profile_id and lifted_at is null;
    if not found then
      raise exception 'This account is not suspended.' using errcode = '23514';
    end if;
  end if;

  select status into seller_status from public.seller_accounts
  where profile_id = target_profile_id and approved_by is not null;
  if suspend and seller_status = 'active' then
    perform public.admin_set_seller_account_status(target_profile_id, 'suspended', clean_reason);
  elsif not suspend and seller_status = 'suspended' then
    perform public.admin_set_seller_account_status(target_profile_id, 'active', clean_reason);
  end if;

  perform private.write_audit_log(
    'admin',
    case when suspend then 'account_suspended' else 'account_restored' end,
    target_profile_id,
    jsonb_build_object('reason', clean_reason)
  );
end;
$$;
revoke all on function public.admin_set_account_suspension(bigint, boolean, text)
  from public, anon;
grant execute on function public.admin_set_account_suspension(bigint, boolean, text)
  to authenticated;
