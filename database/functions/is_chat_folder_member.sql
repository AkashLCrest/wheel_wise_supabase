-- public.is_chat_folder_member(folder text)
--
-- Storage RLS helper: true when the signed-in member belongs to the conversation
-- named by a chat-media folder (<conversation_id>/...). Takes text so a bad
-- folder name simply returns false instead of a uuid cast error.
-- Used by policies on storage.objects (bucket chat-media).
--
-- Created in migration: 20261119040719_chat_media
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.is_chat_folder_member(folder text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.conversation_members
    where conversation_id::text = folder and user_id = (select auth.uid())
  );
$function$;

revoke all on function public.is_chat_folder_member(folder text) from public, anon;
grant execute on function public.is_chat_folder_member(folder text) to authenticated;
