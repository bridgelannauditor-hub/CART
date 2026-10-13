create or replace function public.send_live_message(message_text text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  caller_id bigint := private.current_profile_id();
  active_session public.live_sessions%rowtype;
  new_id uuid;
begin
  if caller_id is null or char_length(trim(message_text)) not between 1 and 300 then
    raise exception 'Comments must be between 1 and 300 characters.' using errcode = '22023';
  end if;
  select * into active_session from public.live_sessions
  where is_live = true order by started_at desc limit 1;
  if not found then raise exception 'This LIVE has ended.' using errcode = '23514'; end if;
  if caller_id <> active_session.seller_id and not active_session.comments_enabled then
    raise exception 'Comments are currently paused.' using errcode = '23514';
  end if;
  if caller_id <> active_session.seller_id and exists (
    select 1 from public.live_blocked_users
    where session_id = active_session.id and user_id = caller_id
  ) then raise exception 'You cannot comment in this LIVE.' using errcode = '42501'; end if;
  insert into public.live_messages (session_id, sender_id, text)
  values (active_session.id, caller_id, trim(message_text)) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.add_live_heart()
returns void language plpgsql security definer set search_path = '' as $$
declare active_id uuid;
begin
  if private.current_profile_id() is null then raise exception 'Authentication required.' using errcode = '42501'; end if;
  select id into active_id from public.live_sessions
  where is_live = true order by started_at desc limit 1;
  if active_id is null then return; end if;
  update public.live_sessions set reaction_counts = jsonb_set(
    reaction_counts, '{heart}',
    to_jsonb(coalesce((reaction_counts ->> 'heart')::integer, 0) + 1)
  ) where id = active_id;
end;
$$;

create or replace function public.hide_live_message(message_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.live_messages m set hidden = true
  where m.id = message_id and exists (
    select 1 from public.live_sessions s
    where s.id = m.session_id and s.seller_id = private.current_profile_id()
  );
  if not found then raise exception 'Only the live seller can moderate comments.' using errcode = '42501'; end if;
end;
$$;

revoke all on function public.send_live_message(text) from public, anon;
revoke all on function public.add_live_heart() from public, anon;
revoke all on function public.hide_live_message(uuid) from public, anon;
grant execute on function public.send_live_message(text) to authenticated;
grant execute on function public.add_live_heart() to authenticated;
grant execute on function public.hide_live_message(uuid) to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'live_sessions') then
    alter publication supabase_realtime add table public.live_sessions;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'live_messages') then
    alter publication supabase_realtime add table public.live_messages;
  end if;
end;
$$;
