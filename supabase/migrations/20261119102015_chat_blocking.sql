-- Blocking in member chat. A member can block another member and unblock them
-- later. While a block exists (either way round) neither of them can send a
-- message in their direct chat. Old messages stay visible.
-- Members only see their own blocks, never who has blocked them.

create table public.blocked_members (
  blocker_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index blocked_members_blocked_idx on public.blocked_members(blocked_id);

alter table public.blocked_members enable row level security;

create policy "members read their own blocks" on public.blocked_members
  for select to authenticated using (blocker_id = (select auth.uid()));
create policy "members block others" on public.blocked_members
  for insert to authenticated with check (blocker_id = (select auth.uid()));
create policy "members unblock" on public.blocked_members
  for delete to authenticated using (blocker_id = (select auth.uid()));

revoke all on public.blocked_members from anon;
revoke update on public.blocked_members from authenticated;

-- True when the signed-in member and the other member of a conversation have
-- blocked each other in either direction (security definer: a member cannot
-- read blocks made against them).
create function public.is_blocked_in_conversation(conv uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.conversation_members other
    join public.blocked_members b
      on (b.blocker_id = other.user_id and b.blocked_id = (select auth.uid()))
      or (b.blocker_id = (select auth.uid()) and b.blocked_id = other.user_id)
    where other.conversation_id = conv
      and other.user_id <> (select auth.uid())
  );
$$;
revoke execute on function public.is_blocked_in_conversation(uuid) from public, anon;
grant execute on function public.is_blocked_in_conversation(uuid) to authenticated;

-- Sending: also refused while blocked (covers send_media_message, which runs
-- with the caller's rights).
drop policy "members send messages as themselves" on public.messages;
create policy "members send messages as themselves" on public.messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and public.is_conversation_member(conversation_id)
    and not public.is_blocked_in_conversation(conversation_id)
  );

-- Uploads: no new chat files while blocked.
drop policy "chat members upload to their own folder" on storage.objects;
create policy "chat members upload to their own folder" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and public.is_chat_folder_member((storage.foldername(name))[1])
    and not public.is_blocked_in_conversation(((storage.foldername(name))[1])::uuid)
  );
