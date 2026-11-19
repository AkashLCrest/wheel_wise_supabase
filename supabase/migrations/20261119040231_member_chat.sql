-- Member-to-member chat (B20). Text now; image/video via message_attachments later.

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  -- 'direct' = one-to-one; 'group' reserved for later.
  kind text not null default 'direct' check (kind in ('direct', 'group')),
  -- For direct chats: the two member ids sorted and joined, so a pair has one chat.
  direct_key text unique,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  check ((kind = 'direct') = (direct_key is not null))
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index conversation_members_user_idx on public.conversation_members(user_id);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind text not null default 'text' check (kind in ('text', 'image', 'video')),
  -- Text, or the optional caption of an image/video.
  body text check (body is null or char_length(body) <= 1000),
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz,
  check (kind <> 'text' or (body is not null and char_length(btrim(body)) > 0))
);
create index messages_conversation_created_idx
  on public.messages(conversation_id, created_at desc);
create index messages_sender_idx on public.messages(sender_id);

-- Files for image/video messages (stored in a private Storage bucket later).
create table public.message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  kind text not null check (kind in ('image', 'video')),
  storage_path text not null,       -- e.g. <conversation_id>/<message_id>/<file>
  mime_type text not null,
  size_bytes bigint check (size_bytes >= 0),
  width int,
  height int,
  duration_ms int,                  -- video only
  thumbnail_path text,              -- video poster / image preview
  created_at timestamptz not null default now()
);
create index message_attachments_message_idx on public.message_attachments(message_id);

-- Membership check used by RLS (security definer avoids recursive policies).
create function public.is_conversation_member(conv uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = conv and user_id = (select auth.uid())
  );
$$;

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_attachments enable row level security;

create policy "members read their conversations" on public.conversations
  for select to authenticated using (public.is_conversation_member(id));

create policy "members read conversation membership" on public.conversation_members
  for select to authenticated using (public.is_conversation_member(conversation_id));
create policy "members update their own read marker" on public.conversation_members
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "members read messages" on public.messages
  for select to authenticated using (public.is_conversation_member(conversation_id));
create policy "members send messages as themselves" on public.messages
  for insert to authenticated
  with check (sender_id = (select auth.uid()) and public.is_conversation_member(conversation_id));

create policy "members read attachments" on public.message_attachments
  for select to authenticated using (
    exists (select 1 from public.messages m
            where m.id = message_id and public.is_conversation_member(m.conversation_id))
  );
create policy "senders add attachments to their messages" on public.message_attachments
  for insert to authenticated with check (
    exists (select 1 from public.messages m
            where m.id = message_id and m.sender_id = (select auth.uid()))
  );

-- Keep the conversation list ordered by latest activity.
create function public.touch_conversation()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.conversations set last_message_at = new.created_at
  where id = new.conversation_id;
  return new;
end;
$$;
create trigger messages_touch_conversation
  after insert on public.messages
  for each row execute function public.touch_conversation();

-- Returns the one-to-one chat with another member, creating it on first use.
create function public.get_or_create_direct_conversation(other_id uuid)
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

-- The signed-in member's chats, latest first, with the other member and last message.
create function public.list_conversations()
returns table (
  conversation_id uuid,
  member_id uuid,
  full_name text,
  membership_id text,
  last_message_id uuid,
  last_message_kind text,
  last_message_body text,
  last_message_sender_id uuid,
  last_message_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select c.id, p.id, p.full_name, p.membership_id,
         m.id, m.kind, m.body, m.sender_id, m.created_at
  from public.conversation_members mine
  join public.conversations c on c.id = mine.conversation_id
  join public.conversation_members other
    on other.conversation_id = c.id and other.user_id <> mine.user_id
  join public.profiles p on p.id = other.user_id
  join lateral (
    select * from public.messages
    where conversation_id = c.id and deleted_at is null
    order by created_at desc limit 1
  ) m on true
  where mine.user_id = (select auth.uid()) and c.kind = 'direct'
  order by c.last_message_at desc;
$$;

revoke execute on function public.is_conversation_member(uuid) from public, anon;
revoke execute on function public.touch_conversation() from public, anon, authenticated;
revoke execute on function public.get_or_create_direct_conversation(uuid) from public, anon;
revoke execute on function public.list_conversations() from public, anon;
grant execute on function public.is_conversation_member(uuid) to authenticated;
grant execute on function public.get_or_create_direct_conversation(uuid) to authenticated;
grant execute on function public.list_conversations() to authenticated;

alter publication supabase_realtime add table public.messages;
