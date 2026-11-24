-- public.list_members()
--
-- RPC: the member directory. Every other member's id, full_name,
-- membership_id and allow_messages (false = not accepting messages).
-- Left out: soft-deleted members (profiles.deleted_at set) and members who
-- turned off "Show me in the member list" (profiles.show_in_member_list).
-- security definer because profiles RLS lets a member read only their own row;
-- only these columns are exposed.
-- App: MembersScreen (supabase.rpc('list_members')).
--
-- Created in migration: 20261118100359_list_members_rpc (deleted members excluded in
-- 20261119104201_soft_delete_account; allow_messages / show_in_member_list added in
-- 20261119111618_chat_privacy_settings; deleted filter restored in 20261119111735_list_members_hide_deleted;
-- has_chat added in 20261124091900_list_members_has_chat, removed in 20261124092622_chat_messages_off_both_ways)
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.list_members()
 RETURNS TABLE(id uuid, full_name text, membership_id text, allow_messages boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p.id, p.full_name, p.membership_id, p.allow_messages
  from public.profiles p
  where p.id <> (select auth.uid())
    and p.deleted_at is null
    and p.show_in_member_list
  order by p.full_name;
$function$;

revoke all on function public.list_members() from public, anon;
grant execute on function public.list_members() to authenticated;
