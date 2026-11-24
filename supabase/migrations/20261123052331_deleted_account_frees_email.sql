-- Deleting an account now frees its email, so signing up again with the same
-- email creates a brand-new account. Reactivating an old account by signing
-- up (reactivate_account) is removed: anyone could call it signed out to
-- guess a deleted member's password and bring the account back.

-- The deleted member's original email, kept for the team (restore / records).
-- Only readable by the member themselves (profiles RLS: own row), and a
-- deleted member can no longer sign in.
alter table public.profiles add column deleted_email text;

-- Marks the signed-in member as deleted, bans their auth user so they cannot
-- sign in again, ends all their sessions and frees their email: the email is
-- saved in profiles.deleted_email and replaced on the auth user (and its email
-- identity) with a placeholder that can never receive mail. Nothing else is
-- removed. Restore (team): clear profiles.deleted_at and
-- auth.users.banned_until, and copy deleted_email back to the auth user and
-- identity, only if no new account has taken that email.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- Accounts deleted before this change: free their emails the same way.
update public.profiles p
set deleted_email = u.email
from auth.users u
where u.id = p.id and p.deleted_at is not null and p.deleted_email is null
  and u.email not like 'deleted+%@deleted.invalid';

update auth.users u
set email = 'deleted+' || u.id || '@deleted.invalid'
from public.profiles p
where p.id = u.id and p.deleted_at is not null
  and u.email not like 'deleted+%@deleted.invalid';

update auth.identities i
set identity_data = i.identity_data
  || jsonb_build_object('email', 'deleted+' || i.user_id || '@deleted.invalid')
from public.profiles p
where p.id = i.user_id and p.deleted_at is not null and i.provider = 'email';

drop function public.reactivate_account(text, text);
