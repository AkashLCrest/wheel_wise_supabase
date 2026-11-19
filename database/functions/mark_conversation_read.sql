-- public.mark_conversation_read(conv uuid)
--
-- RPC: moves the signed-in member's read marker (last_read_at) for a conversation
-- to now; never moves it backwards. The only way members can change
-- conversation_members (they have no direct write access).
-- App: ChatContext markRead() (chat opened/closed, message seen, app resumed).
--
-- Created in migration: 20261119051814_chat_unread_counts
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.mark_conversation_read(conv uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  update public.conversation_members
  set last_read_at = greatest(last_read_at, now())
  where conversation_id = conv and user_id = (select auth.uid());
$function$;

revoke all on function public.mark_conversation_read(conv uuid) from public, anon;
grant execute on function public.mark_conversation_read(conv uuid) to authenticated;
