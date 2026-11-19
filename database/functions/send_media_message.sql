-- public.send_media_message(uuid, text, text, text, text, bigint, integer, integer, integer)
--
-- RPC: saves an image/video message and its attachment row in one transaction,
-- after the app has uploaded the file to chat-media/<conv>/<me>/<file>.
-- Refuses a kind/MIME mismatch, a path outside the caller's folder, or a file
-- that was never uploaded. security INVOKER: the messages/attachments RLS
-- policies still apply (member of the chat, sending as yourself).
-- App: ChatContext sendMedia().
--
-- Created in migration: 20261119040719_chat_media
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.send_media_message(conv uuid, kind text, caption text, storage_path text, mime_type text, size_bytes bigint, width integer, height integer, duration_ms integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  msg uuid;
begin
  if kind not in ('image', 'video') or mime_type not like kind || '/%' then
    raise exception 'invalid media type';
  end if;
  if storage_path not like conv::text || '/' || (select auth.uid())::text || '/%' then
    raise exception 'invalid storage path';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'chat-media' and o.name = storage_path
  ) then
    raise exception 'file not uploaded';
  end if;

  insert into public.messages (conversation_id, kind, body)
  values (conv, kind, nullif(btrim(caption), ''))
  returning id into msg;

  insert into public.message_attachments
    (message_id, kind, storage_path, mime_type, size_bytes, width, height, duration_ms)
  values
    (msg, kind, storage_path, mime_type, size_bytes, width, height, duration_ms);

  return msg;
end;
$function$;

revoke all on function public.send_media_message(uuid, text, text, text, text, bigint, integer, integer, integer) from public, anon;
grant execute on function public.send_media_message(uuid, text, text, text, text, bigint, integer, integer, integer) to authenticated;
