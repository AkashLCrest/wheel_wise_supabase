-- public.set_updated_at()
--
-- Trigger function: sets updated_at = now() on every update.
-- Fired by: triggers profiles_updated_at, user_settings_updated_at.
--
-- Created in migration: 20261117100945_members_and_settings
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

-- Default grants (Postgres lets anyone execute). Harmless: a trigger function
-- cannot be called directly.
