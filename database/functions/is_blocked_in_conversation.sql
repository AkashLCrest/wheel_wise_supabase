-- public.is_blocked_in_conversation(conv uuid)
--
-- Internal helper for the security rules: true when the signed-in member and
-- the other member of the conversation have blocked each other in either
-- direction. Used by the messages insert policy and the chat-media upload
-- policy, so a block stops new messages and files both ways.
-- security definer: members can only read their own blocked_members rows, not
-- blocks made against them.
--
-- Created in migration: 20261119102015_chat_blocking
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.is_blocked_in_conversation(conv uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.conversation_members other
    join public.blocked_members b
      on (b.blocker_id = other.user_id and b.blocked_id = (select auth.uid()))
      or (b.blocker_id = (select auth.uid()) and b.blocked_id = other.user_id)
    where other.conversation_id = conv
      and other.user_id <> (select auth.uid())
  );
$function$;

revoke all on function public.is_blocked_in_conversation(conv uuid) from public, anon;
grant execute on function public.is_blocked_in_conversation(conv uuid) to authenticated;
