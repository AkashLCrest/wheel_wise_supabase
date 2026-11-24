-- Deleted messages are kept so they can be retrieved (e.g. for moderation,
-- or restored by the team by clearing deleted_at). delete_message() now only
-- sets deleted_at: the text, attachments and files all stay. Members no
-- longer see the message, because every query skips deleted rows.

-- Files are never deleted by members now.
drop policy "members delete their own unused chat media" on storage.objects;

-- Text is kept on deleted messages, so text messages always have a body again.
alter table public.messages drop constraint messages_check;
alter table public.messages add constraint messages_check check (
  kind <> 'text' or (body is not null and char_length(btrim(body)) > 0)
);

-- Marks one of the signed-in member's messages as deleted, for both people.
-- Nothing is removed. Calling it on an already deleted message does nothing.
drop function public.delete_message(uuid);
create function public.delete_message(msg uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
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
$$;
revoke execute on function public.delete_message(uuid) from public, anon;
grant execute on function public.delete_message(uuid) to authenticated;
