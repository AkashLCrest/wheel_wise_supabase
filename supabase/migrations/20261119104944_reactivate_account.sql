-- Signing up again with a deleted account's email reactivates it.
-- The app calls this before supabase.auth.signUp. The password must match the
-- account's original password, so knowing the email alone is not enough.
-- Returns true only when a deleted account was reactivated; false otherwise
-- (no such email, not deleted, or wrong password) without saying which.
create or replace function public.reactivate_account(p_email text, p_password text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

revoke all on function public.reactivate_account(text, text) from public;
grant execute on function public.reactivate_account(text, text) to anon, authenticated;
