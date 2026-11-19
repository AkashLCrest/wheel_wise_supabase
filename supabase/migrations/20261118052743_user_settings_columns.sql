-- user_settings: one column per setting instead of a JSON document, plus the
-- last selected number.
--
-- * wheel_type     edition; 'texasTripleZero' was renamed to 'tripleZero' (A1b)
-- * display_style  'standard' | 'highContrast' (Strong)
-- * last_number    last selected pocket as shown on screen: '0'..'36', '00',
--                  '000'; null = nothing selected yet. The app checks it exists
--                  on the chosen wheel.
-- * updated_at     set by the database (record keeping)

alter table public.user_settings
  add column wheel_type text not null default 'european'
    check (wheel_type in ('european', 'americanDoubleZero', 'tripleZero')),
  add column display_style text not null default 'highContrast'
    check (display_style in ('standard', 'highContrast')),
  add column last_number text
    check (last_number ~ '^(0|00|000|[1-9]|[12][0-9]|3[0-6])$');

-- Carry over existing values from the old JSON document.
update public.user_settings
set
  wheel_type = case settings -> 'values' ->> 'wheelType'
    when 'texasTripleZero' then 'tripleZero'
    when 'european' then 'european'
    when 'americanDoubleZero' then 'americanDoubleZero'
    when 'tripleZero' then 'tripleZero'
    else 'european'
  end,
  display_style = case settings -> 'values' ->> 'displayStyle'
    when 'standard' then 'standard'
    else 'highContrast'
  end;

alter table public.user_settings drop column settings;
