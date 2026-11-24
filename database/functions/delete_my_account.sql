-- public.delete_my_account()
--
-- RPC: soft-deletes the signed-in member and frees their email. Sets
-- profiles.deleted_at, saves the email in profiles.deleted_email, replaces the
-- email on the auth user and its email identity with a placeholder
-- (deleted+<user id>@deleted.invalid, never receives mail), bans the auth user
-- (banned_until = infinity) and ends all their sessions. Nothing else is
-- removed: profile, settings, messages, files and feedback stay, and the other
-- member still sees earlier chat messages. Signing up again with the same
-- email creates a brand-new account.
-- Restore (team, in the dashboard): clear profiles.deleted_at and
-- auth.users.banned_until, and copy deleted_email back to auth.users.email and
-- the email identity, only if no new account has taken that email.
-- security definer because members cannot write auth.users, auth.identities
-- or profiles.deleted_at / deleted_email.
-- App: ProfileScreen → Delete account (supabase.rpc('delete_my_account')).
--
-- Created in migration: 20261119104031_delete_account (hard delete), replaced in
-- 20261119104201_soft_delete_account (soft delete) and
-- 20261123052331_deleted_account_frees_email (frees the email)
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid();
  placeholder text;
begin
  if uid is null then
    raise exception 'not signed in';
  end if;
  placeholder := 'deleted+' || uid || '@deleted.invalid';
  update public.profiles p
  set deleted_at = now(),
      deleted_email = u.email
  from auth.users u
  where p.id = uid and u.id = uid and p.deleted_at is null;
  update auth.users
  set email = placeholder,
      banned_until = 'infinity'
  where id = uid;
  update auth.identities
  set identity_data = identity_data || jsonb_build_object('email', placeholder)
  where user_id = uid and provider = 'email';
  delete from auth.sessions where user_id = uid;
end;
$function$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
