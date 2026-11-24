-- Read receipts and typing indicator.
--
-- Read receipts: each member's conversation_members.last_read_at (already
-- readable by both members of a chat) is now published to Realtime, so the
-- sender sees "Seen" as soon as the other member reads.
--
-- Typing: sent as Realtime broadcast messages on a private channel per chat,
-- topic 'typing:<conversation_id>'. Nothing is saved. Only members of that
-- conversation can join the channel, send or receive on it.

alter publication supabase_realtime add table public.conversation_members;

create policy "chat members receive typing" on realtime.messages
  for select to authenticated using (
    realtime.messages.extension = 'broadcast'
    and split_part(realtime.topic(), ':', 1) = 'typing'
    and public.is_chat_folder_member(split_part(realtime.topic(), ':', 2))
  );

create policy "chat members send typing" on realtime.messages
  for insert to authenticated with check (
    realtime.messages.extension = 'broadcast'
    and split_part(realtime.topic(), ':', 1) = 'typing'
    and public.is_chat_folder_member(split_part(realtime.topic(), ':', 2))
  );
