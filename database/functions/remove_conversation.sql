-- public.remove_conversation(conv uuid)
--
-- RPC: "Remove" (delete the chat for me). Sets cleared_at, removed_at and the
-- read marker to now: the history is hidden and the chat leaves the inbox
-- until a new message arrives. Nothing is deleted; the other member sees
-- everything.
-- App: ChatContext removeChat() (member profile → Remove).
--
-- Created in migration: 20261124085835_chat_clear_and_remove
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.remove_conversation(conv uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  update public.conversation_members
  set cleared_at = now(), removed_at = now(),
      last_read_at = greatest(last_read_at, now())
  where conversation_id = conv and user_id = (select auth.uid());
$function$;

revoke all on function public.remove_conversation(conv uuid) from public, anon;
grant execute on function public.remove_conversation(conv uuid) to authenticated;
