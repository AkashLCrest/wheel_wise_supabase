-- public.conversation_cleared_at(conv uuid)
--
-- RLS helper: when the signed-in member's history in a conversation starts
-- (their cleared_at; null = they see everything). Used by the messages read
-- policy, so cleared messages are hidden from that member only.
--
-- Created in migration: 20261124085835_chat_clear_and_remove
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.conversation_cleared_at(conv uuid)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select cleared_at from public.conversation_members
  where conversation_id = conv and user_id = (select auth.uid());
$function$;

revoke all on function public.conversation_cleared_at(conv uuid) from public, anon;
grant execute on function public.conversation_cleared_at(conv uuid) to authenticated;
