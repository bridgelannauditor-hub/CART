-- Keep one conversation per pair and allow sender-owned message edits.
create unique index if not exists conversation_participant_pair_idx
on public.conversations (
  least(participant_ids[1], participant_ids[2]),
  greatest(participant_ids[1], participant_ids[2])
);

grant update (message_text, edited_at) on public.messages to authenticated;

-- Supabase Realtime only emits changes for tables in this publication.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversations'
  ) then
    alter publication supabase_realtime add table public.conversations;
  end if;
end;
$$;
