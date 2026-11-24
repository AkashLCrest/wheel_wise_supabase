-- public.get_or_create_direct_conversation(other_id uuid)
--
-- RPC: returns the 1:1 conversation with another member, creating it (and adding
-- both members) on first use. direct_key (sorted member ids) keeps one chat
-- per pair, even if both members start a chat at the same moment.
-- Refuses with 'messages_off' when either member has allow_messages off, even
-- if they have talked before (off stops all messaging, both ways).
-- security definer: members cannot insert conversations/members directly.
-- App: ChatContext openDirectConversation() (on every send).
--
-- Created in migration: 20261119040231_member_chat (allow_messages check added in 20261119111618_chat_privacy_settings; both ways, chats with messages included, in 20261124092622_chat_messages_off_both_ways)
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.get_or_create_direct_conversation(other_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  if exists (
    select 1 from public.profiles
    where id in (me, other_id) and not allow_messages
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
$function$;

revoke all on function public.get_or_create_direct_conversation(other_id uuid) from public, anon;
grant execute on function public.get_or_create_direct_conversation(other_id uuid) to authenticated;
