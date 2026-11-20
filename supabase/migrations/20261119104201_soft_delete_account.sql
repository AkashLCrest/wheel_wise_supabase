-- Account deletion becomes a soft delete: the member's rows stay (and can be
-- restored by the team), the account is marked deleted and can no longer sign in.
-- Replaces the hard delete from 20261119104031_delete_account.

alter table public.profiles add column deleted_at timestamptz;

-- Files are kept now, so members no longer need to delete chat media.
drop policy "members delete their own chat media" on storage.objects;

-- Marks the signed-in member as deleted, bans their auth user so they cannot
-- sign in again, and ends all their sessions. Restore: clear
-- profiles.deleted_at and auth.users.banned_until.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- Deleted members drop out of the member directory.
create or replace function public.list_members()
returns table(id uuid, full_name text, membership_id text)
language sql
stable security definer
set search_path = ''
as $$
  select p.id, p.full_name, p.membership_id
  from public.profiles p
  where p.id <> (select auth.uid()) and p.deleted_at is null
  order by p.full_name;
$$;

revoke all on function public.list_members() from public, anon;
grant execute on function public.list_members() to authenticated;
