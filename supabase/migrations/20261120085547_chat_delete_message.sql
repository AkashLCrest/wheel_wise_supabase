-- Message deletion: a member can delete their own messages, for both people.
-- The row stays (deleted_at set, text cleared) so chat order and read
-- markers are unaffected, and every query already skips deleted rows. Its
-- attachment rows are removed; the app then deletes the files from
-- chat-media (Storage files can't be deleted from SQL).

-- A deleted text message has no body.
alter table public.messages drop constraint messages_check;
alter table public.messages add constraint messages_check check (
  deleted_at is not null
  or kind <> 'text'
  or (body is not null and char_length(btrim(body)) > 0)
);

-- Deletes one of the signed-in member's messages. Returns the Storage paths
-- of its files for the app to remove (empty if it had none, or was already
-- deleted, e.g. from another device).
create function public.delete_message(msg uuid)
returns text[]
language plpgsql security definer set search_path = ''
as $$
declare
  paths text[];
begin
  if not exists (
    select 1 from public.messages
    where id = msg and sender_id = (select auth.uid())
  ) then
    raise exception 'not your message';
  end if;

  update public.messages
  set deleted_at = now(), body = null
  where id = msg and deleted_at is null;

  with gone as (
    delete from public.message_attachments
    where message_id = msg
    returning storage_path, thumbnail_path
  )
  select coalesce(array_agg(p), '{}') into paths
  from (
    select storage_path as p from gone
    union all
    select thumbnail_path from gone where thumbnail_path is not null
  ) files;

  return paths;
end;
$$;
revoke execute on function public.delete_message(uuid) from public, anon;
grant execute on function public.delete_message(uuid) to authenticated;

-- A member can delete their own chat files, but only ones no message uses
-- any more (i.e. after delete_message removed the attachment).
create policy "members delete their own unused chat media" on storage.objects
  for delete to authenticated using (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and not exists (
      select 1 from public.message_attachments a
      where a.storage_path = objects.name or a.thumbnail_path = objects.name
    )
  );
