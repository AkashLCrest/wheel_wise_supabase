-- Members can edit the text of their own messages (or the caption of an
-- image/video), with no time limit. edited_at records the latest edit and the
-- app shows "Edited". The change reaches the other member live as a Realtime
-- update, like deletions.

create function public.edit_message(msg uuid, new_body text)
returns void
language plpgsql security definer set search_path = ''
as $$
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
  -- Same rule as sending: no edits while either member has blocked the other.
  if public.is_blocked_in_conversation(m.conversation_id) then
    raise exception 'blocked';
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
$$;
revoke execute on function public.edit_message(uuid, text) from public, anon;
grant execute on function public.edit_message(uuid, text) to authenticated;
