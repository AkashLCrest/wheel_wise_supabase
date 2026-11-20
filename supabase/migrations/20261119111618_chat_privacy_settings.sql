-- Chat privacy settings on the member's profile (both on by default).
--   show_in_member_list  off = left out of list_members() (the Members list).
--                        Existing chats are not affected.
--   allow_messages       off = nobody can start a new chat with this member.
--                        Chats that already have messages carry on.

alter table public.profiles
  add column show_in_member_list boolean not null default true,
  add column allow_messages boolean not null default true;

grant update (show_in_member_list, allow_messages) on public.profiles to authenticated;

-- Members list: hide members who opted out; tell the app who accepts new chats.
drop function public.list_members();
create function public.list_members()
returns table (id uuid, full_name text, membership_id text, allow_messages boolean)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.full_name, p.membership_id, p.allow_messages
  from public.profiles p
  where p.id <> (select auth.uid())
    and p.show_in_member_list
  order by p.full_name;
$$;
revoke execute on function public.list_members() from public, anon;
grant execute on function public.list_members() to authenticated;

-- Same as before, plus: refuses to start a chat with a member who has
-- allow_messages off. "Started" = the chat has at least one message, so a
-- member who messaged first can still be replied to.
create or replace function public.get_or_create_direct_conversation(other_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  key text;
  conv uuid;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  if other_id = me or not exists (select 1 from public.profiles where id = other_id) then
    raise exception 'invalid member';
  end if;
  key := least(me::text, other_id::text) || ':' || greatest(me::text, other_id::text);

  if not (select allow_messages from public.profiles where id = other_id)
     and not exists (
       select 1 from public.conversations c
       join public.messages m on m.conversation_id = c.id
       where c.direct_key = key
     ) then
    raise exception 'messages_off';
  end if;

  insert into public.conversations (kind, direct_key)
  values ('direct', key)
  on conflict (direct_key) do nothing
  returning id into conv;

  if conv is null then
    select id into conv from public.conversations where direct_key = key;
  else
    insert into public.conversation_members (conversation_id, user_id)
    values (conv, me), (conv, other_id);
  end if;
  return conv;
end;
$$;
