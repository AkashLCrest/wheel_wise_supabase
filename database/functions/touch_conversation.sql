-- public.touch_conversation()
--
-- Trigger function: sets conversations.last_message_at to the new message's time,
-- so the inbox is ordered by latest activity.
-- Fired by: trigger messages_touch_conversation (messages, after insert).
--
-- Created in migration: 20261119040231_member_chat
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.touch_conversation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.conversations set last_message_at = new.created_at
  where id = new.conversation_id;
  return new;
end;
$function$;

-- Only the database runs this (no one may call it through the API).
revoke execute on function public.touch_conversation() from public, anon, authenticated;
