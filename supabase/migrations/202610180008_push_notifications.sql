-- Phone push notifications (Firebase Cloud Messaging).
--
-- The database decides WHAT to send; the send-push Edge Function delivers it
-- through Firebase. Each phone registers its push address (token) when a user
-- signs in. A new chat message, and every row added to public.notifications
-- (new orders, order status changes, account warnings), is turned into a push
-- for the person it is addressed to, unless they turned push off in Settings.
--
-- The database calls the Edge Function over HTTP with a random shared secret
-- that lives in Supabase Vault, so only this database can trigger a push.

create extension if not exists pg_net with schema extensions;

-- Push addresses --------------------------------------------------------------

create table public.push_tokens (
  token text primary key,
  profile_id bigint not null references public.profiles(id) on delete cascade,
  platform text not null default 'android',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index push_tokens_profile_idx on public.push_tokens (profile_id);

alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from public, anon, authenticated;

-- A phone belongs to whoever signed in last, so a token moves to the new user.
create function public.register_push_token(
  push_token text,
  push_platform text default 'android'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id bigint := private.current_profile_id();
begin
  if caller_id is null then
    raise exception 'Sign in to enable notifications.' using errcode = '42501';
  end if;
  if char_length(coalesce(push_token, '')) not between 20 and 4096 then
    raise exception 'Invalid push token.' using errcode = '22023';
  end if;
  insert into public.push_tokens (token, profile_id, platform)
  values (push_token, caller_id, coalesce(nullif(trim(push_platform), ''), 'android'))
  on conflict (token) do update
    set profile_id = excluded.profile_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;
revoke all on function public.register_push_token(text, text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;

create function public.unregister_push_token(push_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.push_tokens
  where token = unregister_push_token.push_token
    and profile_id = private.current_profile_id();
$$;
revoke all on function public.unregister_push_token(text) from public, anon;
grant execute on function public.unregister_push_token(text) to authenticated;

-- Shared secret -----------------------------------------------------------------

select vault.create_secret(
  encode(extensions.gen_random_bytes(24), 'hex'),
  'push_webhook_secret',
  'Shared secret between the database and the send-push Edge Function'
)
where not exists (
  select 1 from vault.secrets where name = 'push_webhook_secret'
);

-- Called by the Edge Function (service role only) to check the caller.
create function public.verify_push_secret(candidate text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from vault.decrypted_secrets
    where name = 'push_webhook_secret' and decrypted_secret = candidate
  );
$$;
revoke all on function public.verify_push_secret(text) from public, anon, authenticated;
grant execute on function public.verify_push_secret(text) to service_role;

-- Sending -------------------------------------------------------------------------

-- Asks the Edge Function to push to one person. Never raises: a push problem
-- must not stop an order, a message or a notification from being saved.
create function private.send_push(
  target_profile_id bigint,
  push_title text,
  push_body text,
  push_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  push_enabled boolean;
  webhook_secret text;
begin
  select coalesce((notification_preferences ->> 'pushEnabled')::boolean, true)
  into push_enabled
  from public.profiles where id = target_profile_id;
  if not coalesce(push_enabled, false) then return; end if;
  if not exists (
    select 1 from public.push_tokens where profile_id = target_profile_id
  ) then return; end if;

  select decrypted_secret into webhook_secret
  from vault.decrypted_secrets where name = 'push_webhook_secret';
  if webhook_secret is null then return; end if;

  perform net.http_post(
    url := 'https://dhomvejmqkznumjrrarw.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', webhook_secret),
    body := jsonb_build_object(
      'profile_id', target_profile_id,
      'title', left(push_title, 120),
      'body', left(push_body, 300),
      'data', push_data)
  );
exception when others then
  null;
end;
$$;
revoke all on function private.send_push(bigint, text, text, jsonb)
  from public, anon, authenticated;

create function private.push_on_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.send_push(
    new.user_id, new.title, new.body,
    jsonb_build_object(
      'type', new.type,
      'related_id', coalesce(new.related_id::text, ''))
  );
  return new;
end;
$$;
revoke all on function private.push_on_notification() from public, anon, authenticated;

create trigger push_on_notification
  after insert on public.notifications
  for each row execute function private.push_on_notification();

create function private.push_on_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  sender_name text;
  preview text;
begin
  if new.sender_id = new.receiver_id then return new; end if;
  select coalesce(
           nullif(trim(shop_name), ''),
           nullif(trim(first_name || ' ' || last_name), ''),
           'New message')
  into sender_name
  from public.profiles where id = new.sender_id;

  preview := case
    when nullif(trim(new.message_text), '') is not null then new.message_text
    when new.message_type = 'image' then 'Sent a photo'
    when new.message_type = 'video' then 'Sent a video'
    when new.message_type = 'audio' then 'Sent a voice message'
    else 'Sent you a message'
  end;

  perform private.send_push(
    new.receiver_id, sender_name, preview,
    jsonb_build_object(
      'type', 'message',
      'related_id', new.sender_id::text,
      'sender_name', sender_name)
  );
  return new;
end;
$$;
revoke all on function private.push_on_message() from public, anon, authenticated;

create trigger push_on_message
  after insert on public.messages
  for each row execute function private.push_on_message();
