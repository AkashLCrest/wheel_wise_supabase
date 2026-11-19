-- public.list_conversations()
--
-- RPC: the signed-in member's inbox, latest first. One row per direct chat that
-- has at least one message: the other member, the last message, and
-- unread_count (the other member's messages after my last_read_at).
-- App: ChatContext refreshConversations().
--
-- Created in migration: 20261119040231_member_chat (unread_count added in 20261119051814_chat_unread_counts)
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.list_conversations()
 RETURNS TABLE(conversation_id uuid, member_id uuid, full_name text, membership_id text, last_message_id uuid, last_message_kind text, last_message_body text, last_message_sender_id uuid, last_message_at timestamp with time zone, unread_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

revoke all on function public.list_conversations() from public, anon;
grant execute on function public.list_conversations() to authenticated;
