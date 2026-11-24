-- "Allow messages" off now stops all messaging, both ways, in every chat
-- (old ones included), like a block: nobody can message that member, and the
-- member can't send messages either. Old messages stay visible.

-- True when either member of the conversation has allow_messages off.
create function public.is_messaging_off_in_conversation(conv uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.conversation_members cm
    join public.profiles p on p.id = cm.user_id
    where cm.conversation_id = conv and not p.allow_messages
  );
$$;
revoke execute on function public.is_messaging_off_in_conversation(uuid) from public, anon;
grant execute on function public.is_messaging_off_in_conversation(uuid) to authenticated;

-- Sending text (and send_media_message, which runs with the caller's rights).
drop policy "members send messages as themselves" on public.messages;
create policy "members send messages as themselves" on public.messages
  for insert to authenticated with check (
    sender_id = (select auth.uid())
    and public.is_conversation_member(conversation_id)
    and not public.is_blocked_in_conversation(conversation_id)
    and not public.is_messaging_off_in_conversation(conversation_id)
  );

-- Uploading chat photos/videos.
drop policy "chat members upload to their own folder" on storage.objects;
create policy "chat members upload to their own folder" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and public.is_chat_folder_member((storage.foldername(name))[1])
    and not public.is_blocked_in_conversation(((storage.foldername(name))[1])::uuid)
    and not public.is_messaging_off_in_conversation(((storage.foldername(name))[1])::uuid)
  );

-- Editing follows the same rule as sending.
create or replace function public.edit_message(msg uuid, new_body text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  m public.messages;
  cleaned text := nullif(btrim(coalesce(new_body, '')), '');
begin
  select * into m from public.messages
  where id = msg and sender_id = (select auth.uid());
  if not found then
    raise exception 'not your message';
  end if;
  if m.deleted_at is not null then
    raise exception 'message deleted';
  end if;
  -- Same rules as sending: no edits while blocked or while messages are off.
  if public.is_blocked_in_conversation(m.conversation_id) then
    raise exception 'blocked';
  end if;
  if public.is_messaging_off_in_conversation(m.conversation_id) then
    raise exception 'messages_off';
  end if;
  if m.kind = 'text' and cleaned is null then
    raise exception 'empty message';
  end if;
  if char_length(cleaned) > 1000 then
    raise exception 'message too long';
  end if;

  -- Unchanged text is not an edit.
  update public.messages
  set body = cleaned, edited_at = now()
  where id = msg and body is distinct from cleaned;
end;
$$;

-- Opening a chat to send: refused when either member has messages off, even
-- if they have talked before.
create or replace function public.get_or_create_direct_conversation(other_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  key text;
  conv uuid;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  if other_id = me or not exists (select 1 from public.profiles where id = other_id) then
    raise exception 'invalid member';
  end if;
  key := least(me::text, other_id::text) || ':' || greatest(me::text, other_id::text);

  if exists (
    select 1 from public.profiles
    where id in (me, other_id) and not allow_messages
  ) then
    raise exception 'messages_off';
  end if;

  insert into public.conversations (kind, direct_key)
  values ('direct', key)
  on conflict (direct_key) do nothing
  returning id into conv;

  if conv is null then
    select id into conv from public.conversations where direct_key = key;
  else
    insert into public.conversation_members (conversation_id, user_id)
    values (conv, me), (conv, other_id);
  end if;
  return conv;
end;
$$;

-- The inbox also says whether the other member allows messages, so the chat
-- screen knows when to show "not accepting messages".
drop function public.list_conversations();
create function public.list_conversations()
returns table(conversation_id uuid, member_id uuid, full_name text, membership_id text,
  member_allow_messages boolean,
  last_message_id uuid, last_message_kind text, last_message_body text,
  last_message_sender_id uuid, last_message_at timestamptz, unread_count integer)
language sql stable security definer set search_path = ''
as $$
  select c.id, p.id, p.full_name, p.membership_id, p.allow_messages,
         m.id, m.kind, m.body, m.sender_id, m.created_at,
         (select count(*)::int from public.messages u
          where u.conversation_id = c.id
            and u.sender_id <> mine.user_id
            and u.deleted_at is null
            and u.created_at > mine.last_read_at
            and u.created_at > coalesce(mine.cleared_at, '-infinity'))
  from public.conversation_members mine
  join public.conversations c on c.id = mine.conversation_id
  join public.conversation_members other
    on other.conversation_id = c.id and other.user_id <> mine.user_id
  join public.profiles p on p.id = other.user_id
  left join lateral (
    select * from public.messages
    where conversation_id = c.id and deleted_at is null
      and created_at > coalesce(mine.cleared_at, '-infinity')
    order by created_at desc limit 1
  ) m on true
  where mine.user_id = (select auth.uid()) and c.kind = 'direct'
    and (m.id is not null or (mine.cleared_at is not null and mine.removed_at is null))
  order by c.last_message_at desc;
$$;
revoke execute on function public.list_conversations() from public, anon;
grant execute on function public.list_conversations() to authenticated;

-- has_chat is no longer needed: having talked before no longer matters.
drop function public.list_members();
create function public.list_members()
returns table(id uuid, full_name text, membership_id text, allow_messages boolean)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.full_name, p.membership_id, p.allow_messages
  from public.profiles p
  where p.id <> (select auth.uid())
    and p.deleted_at is null
    and p.show_in_member_list
  order by p.full_name;
$$;
revoke execute on function public.list_members() from public, anon;
grant execute on function public.list_members() to authenticated;
