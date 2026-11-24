-- public.is_messaging_off_in_conversation(conv uuid)
--
-- RLS helper: true when either member of the conversation has "Allow
-- messages" off. Then nobody can send in that chat (old ones included): used
-- by the messages insert policy, the chat-media upload policy and
-- edit_message(). Old messages stay visible.
--
-- Created in migration: 20261124092622_chat_messages_off_both_ways
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.is_messaging_off_in_conversation(conv uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.conversation_members cm
    join public.profiles p on p.id = cm.user_id
    where cm.conversation_id = conv and not p.allow_messages
  );
$function$;

revoke all on function public.is_messaging_off_in_conversation(conv uuid) from public, anon;
grant execute on function public.is_messaging_off_in_conversation(conv uuid) to authenticated;
