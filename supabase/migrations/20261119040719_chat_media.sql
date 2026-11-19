-- Image/video messages: private Storage bucket + one call to save message and attachment.
-- File path: <conversation_id>/<sender_id>/<file name>

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-media', 'chat-media', false,
  52428800, -- 50 MB
  array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp', 'image/gif',
        'video/mp4', 'video/quicktime', 'video/3gpp', 'video/webm']
);

-- True when the signed-in member belongs to the conversation named by a folder.
create function public.is_chat_folder_member(folder text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id::text = folder and user_id = (select auth.uid())
  );
$$;
revoke execute on function public.is_chat_folder_member(text) from public, anon;
grant execute on function public.is_chat_folder_member(text) to authenticated;

create policy "chat members read chat media" on storage.objects
  for select to authenticated using (
    bucket_id = 'chat-media'
    and public.is_chat_folder_member((storage.foldername(name))[1])
  );

create policy "chat members upload to their own folder" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and public.is_chat_folder_member((storage.foldername(name))[1])
  );

comment on column public.message_attachments.storage_path is
  'Path in the chat-media bucket: <conversation_id>/<sender_id>/<file name>';

-- Saves an image/video message and its attachment together (runs with the
-- caller's rights, so the messages/attachments RLS policies still apply).
create function public.send_media_message(
  conv uuid,
  kind text,
  caption text,
  storage_path text,
  mime_type text,
  size_bytes bigint,
  width int,
  height int,
  duration_ms int
)
returns uuid
language plpgsql security invoker set search_path = ''
as $$
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
$$;
revoke execute on function public.send_media_message(uuid, text, text, text, text, bigint, int, int, int) from public, anon;
grant execute on function public.send_media_message(uuid, text, text, text, text, bigint, int, int, int) to authenticated;
