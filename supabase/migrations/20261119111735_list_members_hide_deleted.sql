-- Restores the deleted-account filter in list_members(), which
-- 20261119111618_chat_privacy_settings dropped by mistake when it added
-- show_in_member_list / allow_messages. Deleted members and members who
-- hid themselves both stay out of the Members list.
create or replace function public.list_members()
returns table (id uuid, full_name text, membership_id text, allow_messages boolean)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.full_name, p.membership_id, p.allow_messages
  from public.profiles p
  where p.id <> (select auth.uid())
    and p.deleted_at is null
    and p.show_in_member_list
  order by p.full_name;
$$;
revoke execute on function public.list_members() from public, anon;
grant execute on function public.list_members() to authenticated;
