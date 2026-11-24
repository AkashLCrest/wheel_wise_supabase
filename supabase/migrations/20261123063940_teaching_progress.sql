-- Brain De Fogger™ teaching (A12): where each member is in the 8 lessons, so
-- they can pick up where they left off on any device.
--
-- * status        'new' (not opened yet) | 'started' | 'skipped' | 'completed'.
--                 The app opens the lessons by itself after sign-in until the
--                 member completes or skips them.
-- * lesson, step  the step the member was last on (0-based)
-- * done_lessons  lessons finished (0-based lesson numbers)
-- * saved_at      when the app saved this progress (set by the app, so the
--                 newer of the device copy and this row wins)
create table public.teaching_progress (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  status       text not null default 'new'
               check (status in ('new', 'started', 'skipped', 'completed')),
  lesson       smallint not null default 0 check (lesson between 0 and 7),
  step         smallint not null default 0 check (step between 0 and 9),
  done_lessons smallint[] not null default '{}'
               check (done_lessons <@ array[0,1,2,3,4,5,6,7]::smallint[]),
  saved_at     timestamptz not null default now()
);

comment on table public.teaching_progress is
  'Brain De Fogger lesson progress, one row per member.';

alter table public.teaching_progress enable row level security;

create policy "Members read their own teaching progress"
  on public.teaching_progress for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Members insert their own teaching progress"
  on public.teaching_progress for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Members update their own teaching progress"
  on public.teaching_progress for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.teaching_progress from anon;
revoke delete, truncate on public.teaching_progress from authenticated;
grant select, insert, update on public.teaching_progress to authenticated;
