-- public.delete_message(msg uuid)
--
-- RPC: marks one of the signed-in member's own messages as deleted, for both
-- people, by setting deleted_at. Nothing is removed: the text, attachments
-- and files stay, so the message can be retrieved (moderation) or restored by
-- the team by clearing deleted_at. Every member-facing query skips deleted
-- rows. Refuses another member's message; does nothing if already deleted.
-- App: ChatContext deleteMessage() (long-press a message → Delete).
--
-- Created in migration: 20261120085547_chat_delete_message
-- Replaced in migration: 20261120090217_chat_keep_deleted_messages (soft delete only)
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.delete_message(msg uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not exists (
    select 1 from public.messages
    where id = msg and sender_id = (select auth.uid())
  ) then
    raise exception 'not your message';
  end if;

  update public.messages
  set deleted_at = now()
  where id = msg and deleted_at is null;
end;
$function$;

revoke all on function public.delete_message(msg uuid) from public, anon;
grant execute on function public.delete_message(msg uuid) to authenticated;
