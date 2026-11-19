-- public.list_members()
--
-- RPC: every other member's id, full_name and membership_id (member directory).
-- security definer because profiles RLS lets a member read only their own row;
-- only these three columns are exposed.
-- App: MembersScreen (supabase.rpc('list_members')).
--
-- Created in migration: 20261118100359_list_members_rpc
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.list_members()
 RETURNS TABLE(id uuid, full_name text, membership_id text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p.id, p.full_name, p.membership_id
  from public.profiles p
  where p.id <> (select auth.uid())
  order by p.full_name;
$function$;

revoke all on function public.list_members() from public, anon;
grant execute on function public.list_members() to authenticated;
