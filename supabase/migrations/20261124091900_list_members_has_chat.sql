-- list_members() also returns has_chat: true when the signed-in member and
-- that member already have messages together. Same check as the messages_off
-- rule in get_or_create_direct_conversation(), so the app only shows "not
-- accepting messages" when a message would really be refused (a chat removed
-- from the inbox still counts).
drop function public.list_members();
create function public.list_members()
returns table(id uuid, full_name text, membership_id text, allow_messages boolean, has_chat boolean)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.full_name, p.membership_id, p.allow_messages,
         exists (
           select 1 from public.conversations c
           join public.messages m on m.conversation_id = c.id
           where c.direct_key = least((select auth.uid())::text, p.id::text)
                                || ':' || greatest((select auth.uid())::text, p.id::text)
         )
  from public.profiles p
  where p.id <> (select auth.uid())
    and p.deleted_at is null
    and p.show_in_member_list
  order by p.full_name;
$$;
revoke execute on function public.list_members() from public, anon;
grant execute on function public.list_members() to authenticated;
