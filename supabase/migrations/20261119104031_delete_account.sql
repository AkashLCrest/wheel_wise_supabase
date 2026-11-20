-- Account deletion (in-app "Delete account").
-- Members may delete chat files they uploaded (their own folder), so the app
-- can clear their media before the account goes.
create policy "members delete their own chat media"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  );

-- Deletes the signed-in member's auth user. Every member table cascades from
-- it: profile, settings, chat memberships, messages, attachments, feedback, blocks.
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
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
