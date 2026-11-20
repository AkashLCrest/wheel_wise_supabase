-- Settings: show or hide the clock face (12 hours + 38 sub-markers) around
-- the wheel. On by default; purely visual, never affects pocket order.
alter table public.user_settings
  add column show_clock_face boolean not null default true;
