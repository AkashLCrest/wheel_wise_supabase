-- Triggers (reference copy of the live definitions, pg_get_triggerdef).
-- Do not apply this file; change triggers with a new migration.

-- Create the member's profile on sign-up.            (20261117100945_members_and_settings)
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Keep updated_at current.                           (20261117100945_members_and_settings)
CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER user_settings_updated_at BEFORE UPDATE ON public.user_settings FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Order the chat inbox by latest message.            (20261119040231_member_chat)
CREATE TRIGGER messages_touch_conversation AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION touch_conversation();

-- Event trigger (Supabase-managed, not in our migrations): ensure_rls runs
-- public.rls_auto_enable() on every CREATE TABLE so new public tables get RLS.
