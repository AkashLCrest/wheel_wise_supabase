-- public.get_my_membership()
--
-- RPC: the signed-in member's membership, from their verified App Store /
-- Google Play subscriptions (store_subscriptions). One row: the subscription
-- that gives access (status 'active' or 'grace_period' and expires_at in the
-- future), else the one with the latest expiry. No row = never subscribed.
-- security invoker: store_subscriptions RLS already limits a member to their
-- own rows.
-- App: MembershipContext (supabase.rpc('get_my_membership')), on sign-in, when
-- the app returns to the foreground, when the paid period ends and after a
-- purchase or restore is verified.
--
-- Created in migration: 20261125100531_membership_store_subscriptions
-- Reference copy of the live definition (pg_get_functiondef). Do not apply
-- this file; change functions with a new migration.

CREATE OR REPLACE FUNCTION public.get_my_membership()
 RETURNS TABLE(is_member boolean, platform text, product_id text, plan_id text, status text, expires_at timestamp with time zone, auto_renew boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select
    s.status in ('active', 'grace_period') and s.expires_at > now(),
    s.platform,
    s.product_id,
    s.plan_id,
    s.status,
    s.expires_at,
    s.auto_renew
  from public.store_subscriptions s
  where s.user_id = (select auth.uid())
  order by
    (s.status in ('active', 'grace_period') and s.expires_at > now()) desc,
    s.expires_at desc nulls last
  limit 1;
$function$;

revoke all on function public.get_my_membership() from public, anon;
grant execute on function public.get_my_membership() to authenticated;
