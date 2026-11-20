-- public.reactivate_account(p_email text, p_password text)
--
-- RPC: reactivates a soft-deleted account when someone signs up again with its
-- email AND its original password. Clears profiles.deleted_at and
-- auth.users.banned_until; the member then signs in normally with all their data.
-- Returns true only when a deleted account was reactivated; false for an unknown
-- email, an active account or a wrong password, without saying which.
-- security definer because it reads auth.users; callable signed out (anon).
-- App: SignUpScreen, before supabase.auth.signUp.
--
-- Created in migration: 20261119104944_reactivate_account
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.reactivate_account(p_email text, p_password text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid;
begin
  select u.id into uid
  from auth.users u
  join public.profiles p on p.id = u.id
  where lower(u.email) = lower(trim(p_email))
    and p.deleted_at is not null
    and u.encrypted_password = extensions.crypt(p_password, u.encrypted_password);
  if uid is null then
    return false;
  end if;
  update public.profiles set deleted_at = null where id = uid;
  update auth.users set banned_until = null where id = uid;
  return true;
end;
$function$;

revoke all on function public.reactivate_account(text, text) from public;
grant execute on function public.reactivate_account(text, text) to anon, authenticated;
