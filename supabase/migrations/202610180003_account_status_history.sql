-- Account status history for administrators.
--
-- Reads the immutable audit log for one account and returns only the events
-- that change or review its status: suspensions and restorations, seller
-- access changes, and the seller application decisions. Noisy events (document
-- views, verification sessions, email challenges) are left out.

create or replace function public.admin_account_history(
  target_profile_id bigint,
  row_limit integer default 100
)
returns table (
  event_id bigint,
  action text,
  actor_kind text,
  actor_email text,
  reason text,
  occurred_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select l.id, l.action, l.actor_kind, p.email,
         nullif(trim(coalesce(l.details ->> 'reason', l.details ->> 'note', '')), ''),
         l.created_at
  from public.audit_logs l
  left join public.profiles p on p.auth_user_id = l.actor_auth_user_id
  where l.target_profile_id = admin_account_history.target_profile_id
    and (
      l.action in (
        'account_suspended', 'account_restored',
        'seller_account_suspended', 'seller_account_active', 'seller_account_revoked',
        'application_submitted', 'application_approve', 'application_reject',
        'application_appealed', 'shop_submitted', 'identity_review_resolved'
      )
    )
  order by l.created_at desc, l.id desc
  limit least(greatest(coalesce(admin_account_history.row_limit, 100), 1), 500);
end;
$$;
revoke all on function public.admin_account_history(bigint, integer) from public, anon;
grant execute on function public.admin_account_history(bigint, integer) to authenticated;
