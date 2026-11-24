-- public.list_conversations()
--
-- RPC: the signed-in member's inbox, latest first. One row per direct chat that
-- has a message after my cleared_at, plus cleared (not removed) chats with
-- nothing new (last message columns null): the other member, the last
-- message, member_allow_messages (the other member's "Allow messages"), and unread_count (the other member's messages after my
-- last_read_at and cleared_at). Removed chats return once a new message arrives.
-- App: ChatContext refreshConversations().
--
-- Created in migration: 20261119040231_member_chat (unread_count added in 20261119051814_chat_unread_counts; cleared/removed chats in 20261124085835_chat_clear_and_remove; member_allow_messages in 20261124092622_chat_messages_off_both_ways)
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.list_conversations()
 RETURNS TABLE(conversation_id uuid, member_id uuid, full_name text, membership_id text, member_allow_messages boolean, last_message_id uuid, last_message_kind text, last_message_body text, last_message_sender_id uuid, last_message_at timestamp with time zone, unread_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

revoke all on function public.list_conversations() from public, anon;
grant execute on function public.list_conversations() to authenticated;
