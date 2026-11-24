-- "Clear chat" and "Remove" (delete the chat for me), both for the signed-in
-- member only. Nothing is deleted: the other member still sees everything and
-- the team can still retrieve every message.
--   cleared_at: messages up to this moment are hidden from this member.
--   removed_at: the chat is also left out of this member's inbox until a new
--               message arrives (then it shows again with only new messages).

alter table public.conversation_members
  add column cleared_at timestamptz,
  add column removed_at timestamptz;

-- When the signed-in member's history in a conversation starts (null = all).
create function public.conversation_cleared_at(conv uuid)
returns timestamptz
language sql stable security definer set search_path = ''
as $$
  select cleared_at from public.conversation_members
  where conversation_id = conv and user_id = (select auth.uid());
$$;
revoke execute on function public.conversation_cleared_at(uuid) from public, anon;
grant execute on function public.conversation_cleared_at(uuid) to authenticated;

-- Members read only the messages after their own cleared_at. Attachments
-- follow, because their policy looks the message up through this one; so does
-- Realtime, which applies the same rules.
drop policy "members read messages" on public.messages;
create policy "members read messages" on public.messages
  for select to authenticated using (
    public.is_conversation_member(conversation_id)
    and created_at > coalesce(public.conversation_cleared_at(conversation_id), '-infinity')
  );

-- Hides the history for me; the chat stays in my inbox.
create function public.clear_conversation(conv uuid)
returns void
language sql security definer set search_path = ''
as $$
  update public.conversation_members
  set cleared_at = now(), removed_at = null,
      last_read_at = greatest(last_read_at, now())
  where conversation_id = conv and user_id = (select auth.uid());
$$;
revoke execute on function public.clear_conversation(uuid) from public, anon;
grant execute on function public.clear_conversation(uuid) to authenticated;

-- Hides the history for me and takes the chat out of my inbox.
create function public.remove_conversation(conv uuid)
returns void
language sql security definer set search_path = ''
as $$
  update public.conversation_members
  set cleared_at = now(), removed_at = now(),
      last_read_at = greatest(last_read_at, now())
  where conversation_id = conv and user_id = (select auth.uid());
$$;
revoke execute on function public.remove_conversation(uuid) from public, anon;
grant execute on function public.remove_conversation(uuid) to authenticated;

-- Inbox: counts and last message start after my cleared_at. A cleared chat
-- with nothing new still shows (no last message); a removed one shows again
-- only once a new message arrives.
create or replace function public.list_conversations()
returns table(conversation_id uuid, member_id uuid, full_name text, membership_id text,
  last_message_id uuid, last_message_kind text, last_message_body text,
  last_message_sender_id uuid, last_message_at timestamptz, unread_count integer)
language sql stable security definer set search_path = ''
as $$
  select c.id, p.id, p.full_name, p.membership_id,
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
