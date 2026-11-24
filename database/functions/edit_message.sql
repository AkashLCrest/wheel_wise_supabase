-- public.edit_message(msg uuid, new_body text)
--
-- RPC: changes the text of one of the signed-in member's own messages (or the
-- caption of an image/video) and sets edited_at. No time limit. The text is
-- trimmed; text messages can't become empty (an empty caption is saved as
-- null); max 1000 characters. Refuses another member's message, a deleted
-- message, and edits while either member has blocked the other or has
-- "Allow messages" off ('messages_off'). Unchanged
-- text does nothing. The other member gets the edit live (Realtime update).
-- App: ChatContext editMessage() (long-press a message → Edit).
--
-- Created in migration: 20261124082522_chat_edit_message (messages_off check added in 20261124092622_chat_messages_off_both_ways)
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.edit_message(msg uuid, new_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  m public.messages;
  cleaned text := nullif(btrim(coalesce(new_body, '')), '');
begin
  select * into m from public.messages
  where id = msg and sender_id = (select auth.uid());
  if not found then
    raise exception 'not your message';
  end if;
  if m.deleted_at is not null then
    raise exception 'message deleted';
  end if;
  -- Same rules as sending: no edits while blocked or while messages are off.
  if public.is_blocked_in_conversation(m.conversation_id) then
    raise exception 'blocked';
  end if;
  if public.is_messaging_off_in_conversation(m.conversation_id) then
    raise exception 'messages_off';
  end if;
  if m.kind = 'text' and cleaned is null then
    raise exception 'empty message';
  end if;
  if char_length(cleaned) > 1000 then
    raise exception 'message too long';
  end if;

  -- Unchanged text is not an edit.
  update public.messages
  set body = cleaned, edited_at = now()
  where id = msg and body is distinct from cleaned;
end;
$function$;

revoke all on function public.edit_message(msg uuid, new_body text) from public, anon;
grant execute on function public.edit_message(msg uuid, new_body text) to authenticated;
