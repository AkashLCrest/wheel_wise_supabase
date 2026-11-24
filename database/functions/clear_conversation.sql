-- public.clear_conversation(conv uuid)
--
-- RPC: "Clear chat" for the signed-in member only. Sets cleared_at (and the
-- read marker) to now and clears removed_at, so the history is hidden but the
-- chat stays in the inbox. Nothing is deleted; the other member sees everything.
-- App: ChatContext clearChat() (member profile → Clear chat).
--
-- Created in migration: 20261124085835_chat_clear_and_remove
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.clear_conversation(conv uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  update public.conversation_members
  set cleared_at = now(), removed_at = null,
      last_read_at = greatest(last_read_at, now())
  where conversation_id = conv and user_id = (select auth.uid());
$function$;

revoke all on function public.clear_conversation(conv uuid) from public, anon;
grant execute on function public.clear_conversation(conv uuid) to authenticated;
