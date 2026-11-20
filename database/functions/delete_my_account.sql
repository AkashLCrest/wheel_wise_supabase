-- public.delete_my_account()
--
-- RPC: soft-deletes the signed-in member. Sets profiles.deleted_at, bans the auth
-- user (banned_until = infinity) so they cannot sign in again, and ends all their
-- sessions. Nothing is removed: profile, settings, messages, files and feedback
-- stay, and the other member still sees earlier chat messages.
-- Restore (team, in the dashboard): clear profiles.deleted_at and auth.users.banned_until.
-- security definer because members cannot write auth.users or profiles.deleted_at.
-- App: ProfileScreen → Delete account (supabase.rpc('delete_my_account')).
--
-- Created in migration: 20261119104031_delete_account (hard delete), replaced in
-- 20261119104201_soft_delete_account (soft delete)
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  update public.profiles set deleted_at = now()
  where id = auth.uid() and deleted_at is null;
  update auth.users set banned_until = 'infinity'
  where id = auth.uid();
  delete from auth.sessions where user_id = auth.uid();
end;
$function$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
