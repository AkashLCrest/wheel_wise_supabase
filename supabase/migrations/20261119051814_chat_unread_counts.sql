-- Unread counts. Also closes a hole: the old update policy let a member change
-- any column of their own conversation_members row (e.g. conversation_id, to
-- move into someone else's chat). Read markers now change only through
-- mark_conversation_read().

drop policy "members update their own read marker" on public.conversation_members;
revoke insert, update, delete on public.conversation_members from anon, authenticated;

-- Marks everything in the conversation as read for the signed-in member.
create function public.mark_conversation_read(conv uuid)
returns void
language sql security definer set search_path = ''
as $$
  update public.conversation_members
  set last_read_at = greatest(last_read_at, now())
  where conversation_id = conv and user_id = (select auth.uid());
$$;
revoke execute on function public.mark_conversation_read(uuid) from public, anon;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

-- Same as before, plus unread_count: messages from the other member newer
-- than my read marker.
drop function public.list_conversations();
create function public.list_conversations()
returns table (
  conversation_id uuid,
  member_id uuid,
  full_name text,
  membership_id text,
  last_message_id uuid,
  last_message_kind text,
  last_message_body text,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  unread_count int
)
language sql stable security definer set search_path = ''
as $$
  select c.id, p.id, p.full_name, p.membership_id,
         m.id, m.kind, m.body, m.sender_id, m.created_at,
         (select count(*)::int from public.messages u
          where u.conversation_id = c.id
            and u.sender_id <> mine.user_id
            and u.deleted_at is null
            and u.created_at > mine.last_read_at)
  from public.conversation_members mine
  join public.conversations c on c.id = mine.conversation_id
  join public.conversation_members other
    on other.conversation_id = c.id and other.user_id <> mine.user_id
  join public.profiles p on p.id = other.user_id
  join lateral (
    select * from public.messages
    where conversation_id = c.id and deleted_at is null
    order by created_at desc limit 1
  ) m on true
  where mine.user_id = (select auth.uid()) and c.kind = 'direct'
  order by c.last_message_at desc;
$$;
revoke execute on function public.list_conversations() from public, anon;
grant execute on function public.list_conversations() to authenticated;
