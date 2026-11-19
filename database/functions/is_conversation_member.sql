-- public.is_conversation_member(conv uuid)
--
-- RLS helper: true when the signed-in member belongs to the conversation.
-- security definer so policies on conversation_members can use it without
-- recursing into themselves.
-- Used by policies on: conversations, conversation_members, messages,
-- message_attachments (and so by Realtime, which applies the same RLS).
--
-- Created in migration: 20261119040231_member_chat
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.is_conversation_member(conv uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = conv and user_id = (select auth.uid())
  );
$function$;

revoke all on function public.is_conversation_member(conv uuid) from public, anon;
grant execute on function public.is_conversation_member(conv uuid) to authenticated;
