-- Member directory for chat (B20): every other member's name and member ID.
-- security definer because profiles RLS only lets a member read their own row;
-- this exposes just these three columns, and only to signed-in members.

create or replace function public.list_members()
returns table (id uuid, full_name text, membership_id text)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.full_name, p.membership_id
  from public.profiles p
  where p.id <> (select auth.uid())
  order by p.full_name;
$$;
revoke all on function public.list_members() from public, anon;
grant execute on function public.list_members() to authenticated;
