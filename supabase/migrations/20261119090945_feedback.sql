-- Member feedback (M, Group 2B). Members can send feedback; only the team
-- (Supabase dashboard / service role) can read it.
create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  topic text not null check (topic in ('bug', 'idea', 'wheel', 'teaching', 'other')),
  rating smallint not null check (rating between 1 and 5),
  message text not null check (char_length(btrim(message)) > 0 and char_length(message) <= 2000),
  language text,
  platform text check (platform in ('ios', 'android')),
  status text not null default 'new' check (status in ('new', 'reviewed', 'closed')),
  created_at timestamptz not null default now()
);

comment on table public.feedback is
  'Member feedback from the app. Members can only insert their own rows; the team reviews them in the dashboard.';
comment on column public.feedback.rating is 'How helpful the app is so far, 1-5 (shown as wheels in the app).';
comment on column public.feedback.language is 'App language when the feedback was sent.';
comment on column public.feedback.status is 'Team review state: new, reviewed or closed.';

alter table public.feedback enable row level security;

create index feedback_user_id_idx on public.feedback (user_id);
create index feedback_created_at_idx on public.feedback (created_at desc);

-- Members can send feedback as themselves. No select/update/delete policies.
create policy "Members send their own feedback" on public.feedback
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

revoke all on public.feedback from anon;
revoke select, update, delete, truncate on public.feedback from authenticated;
grant insert on public.feedback to authenticated;
