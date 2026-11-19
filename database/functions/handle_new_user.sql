-- public.handle_new_user()
--
-- Trigger function: creates the member's `profiles` row when someone signs up.
-- Reads full_name and language from the sign-up metadata the app sends.
-- Fired by: trigger on_auth_user_created (auth.users, after insert).
--
-- Created in migration: 20261117100945_members_and_settings (grants: 20261117101054_harden_policies)
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into public.profiles (id, full_name, language)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'language', 'en')
  );
  return new;
end;
$function$;

-- Only the database runs this (no one may call it through the API).
revoke execute on function public.handle_new_user() from public, anon, authenticated;
