-- WHEEL WISE™ — members (2B registration) + synced settings (A13).
--
-- profiles       one row per member: name, chosen language, membership ID
-- user_settings  the A13 settings document (edition + display style)
--
-- Chat, QR/booklet links and ordering are NOT created yet: their rules are
-- still to be agreed with the client.

-- --------------------------------------------------------------------------
-- profiles
-- --------------------------------------------------------------------------
create sequence if not exists public.membership_number_seq start 100001;

create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  full_name     text not null default '',
  -- Chosen at registration, changeable in the profile (BCP-47, e.g. 'en').
  language      text not null default 'en',
  -- Member ID shown in the app / printed with the booklet, e.g. WW100001.
  membership_id text not null unique
                default 'WW' || nextval('public.membership_number_seq'),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Members read their own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Members update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- Members may change only their name and language (not the membership ID).
revoke update on public.profiles from authenticated, anon;
grant update (full_name, language) on public.profiles to authenticated;

-- Create the profile automatically when someone signs up. The app sends
-- full_name and language in the sign-up metadata.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, language)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'language', 'en')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- --------------------------------------------------------------------------
-- user_settings (A13 — same JSON as the app's SettingsDocument)
-- --------------------------------------------------------------------------
create table public.user_settings (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  settings   jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.user_settings enable row level security;

create policy "Members read their own settings"
  on public.user_settings for select
  using (auth.uid() = user_id);

create policy "Members insert their own settings"
  on public.user_settings for insert
  with check (auth.uid() = user_id);

create policy "Members update their own settings"
  on public.user_settings for update
  using (auth.uid() = user_id);

-- --------------------------------------------------------------------------
-- keep updated_at current
-- --------------------------------------------------------------------------
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger user_settings_updated_at
  before update on public.user_settings
  for each row execute function public.set_updated_at();
