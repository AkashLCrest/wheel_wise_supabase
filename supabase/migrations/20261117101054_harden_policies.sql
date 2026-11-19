-- Advisor fixes for 20261117100945_members_and_settings.
--
-- 1. handle_new_user() runs only from the sign-up trigger; nobody may call it
--    through the API.
-- 2. Policies use (select auth.uid()) so it is evaluated once per query, not
--    once per row, and apply only to signed-in users.

revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- profiles
drop policy "Members read their own profile" on public.profiles;
drop policy "Members update their own profile" on public.profiles;

create policy "Members read their own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy "Members update their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- user_settings
drop policy "Members read their own settings" on public.user_settings;
drop policy "Members insert their own settings" on public.user_settings;
drop policy "Members update their own settings" on public.user_settings;

create policy "Members read their own settings"
  on public.user_settings for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Members insert their own settings"
  on public.user_settings for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Members update their own settings"
  on public.user_settings for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
