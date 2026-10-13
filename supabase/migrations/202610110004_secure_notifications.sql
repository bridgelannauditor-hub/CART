-- Create notifications through a checked RPC instead of granting clients
-- unrestricted insert access to another user's notification inbox.

create or replace function public.create_notification(
  target_user_id bigint,
  notification_title text,
  notification_body text,
  notification_type text,
  notification_related_id bigint default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id bigint := private.current_profile_id();
  preferences jsonb;
  new_id uuid;
begin
  if caller_id is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  if notification_type in ('order', 'order_status') then
    if notification_related_id is null or not exists (
      select 1
      from public.orders o
      where o.id = notification_related_id
        and (caller_id = o.customer_id or caller_id = any(o.seller_ids))
        and (target_user_id = o.customer_id or target_user_id = any(o.seller_ids))
    ) then
      raise exception 'The notification participants do not match this order.'
        using errcode = '42501';
    end if;
  elsif notification_type = 'live' then
    if notification_related_id <> caller_id or not exists (
      select 1 from public.shop_follows f
      where f.seller_id = caller_id and f.follower_id = target_user_id
    ) then
      raise exception 'The target does not follow this seller.'
        using errcode = '42501';
    end if;
  else
    raise exception 'Unsupported notification type.' using errcode = '22023';
  end if;

  select p.notification_preferences into preferences
  from public.profiles p where p.id = target_user_id;

  if preferences is null
     or coalesce((preferences ->> 'pushEnabled')::boolean, true) is false
     or (notification_type in ('order', 'order_status') and
         coalesce((preferences ->> 'orderUpdates')::boolean, true) is false)
     or (notification_type = 'live' and
         coalesce((preferences ->> 'promoOffers')::boolean, true) is false) then
    return null;
  end if;

  insert into public.notifications (
    user_id, created_by_id, title, body, type, related_id
  ) values (
    target_user_id, caller_id, notification_title, notification_body,
    notification_type, notification_related_id
  ) returning id into new_id;

  return new_id;
end;
$$;

revoke all on function public.create_notification(bigint, text, text, text, bigint)
from public, anon;
grant execute on function public.create_notification(bigint, text, text, text, bigint)
to authenticated;
