-- Membership (App Store / Google Play subscriptions), linked to the member's
-- WHEEL WISE account (their email login), not to the device.
--
-- store_subscriptions: one row per store subscription, written only by the
-- edge functions (service role) after the purchase has been checked with
-- Apple / Google. A subscription belongs to exactly one account.
--
-- * platform               'apple' | 'google'
-- * store_subscription_id  Apple: originalTransactionId (stays the same across
--                          renewals). Google: the purchase token.
-- * product_id, plan_id    store product and the app's plan ('annual' / 'monthly')
-- * status                 'active'         paid up (auto_renew says whether it renews)
--                          'grace_period'   renewal payment failing, store still gives access
--                          'billing_retry'  renewal payment failing, no access
--                          'on_hold' | 'paused' (Google), no access
--                          'pending'        payment not completed yet (Google), no access
--                          'expired' | 'revoked' (refunded) | 'replaced' (Google
--                          plan change: a newer purchase token took over)
-- * expires_at             end of the paid (or grace) period
-- * environment            'production' | 'sandbox' (Apple sandbox / Google test purchase)
-- * store_data             last decoded store response, for support
--
-- A member has access while one of their rows is active or in its grace
-- period and expires_at is in the future (get_my_membership()).
create table public.store_subscriptions (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references auth.users (id) on delete cascade,
  platform               text not null check (platform in ('apple', 'google')),
  store_subscription_id  text not null,
  product_id             text not null,
  plan_id                text check (plan_id in ('annual', 'monthly')),
  status                 text not null check (status in (
                           'active', 'grace_period', 'billing_retry', 'on_hold',
                           'paused', 'pending', 'expired', 'revoked', 'replaced')),
  expires_at             timestamptz,
  auto_renew             boolean not null default false,
  environment            text not null check (environment in ('production', 'sandbox')),
  store_data             jsonb not null default '{}'::jsonb,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (platform, store_subscription_id)
);

create index store_subscriptions_user_id_idx
  on public.store_subscriptions (user_id);

comment on table public.store_subscriptions is
  'Verified App Store / Google Play membership subscriptions, one row per store subscription. Written only by the edge functions.';

create trigger store_subscriptions_updated_at
  before update on public.store_subscriptions
  for each row execute function public.set_updated_at();

alter table public.store_subscriptions enable row level security;

create policy "Members read their own store subscriptions"
  on public.store_subscriptions for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.store_subscriptions from anon, authenticated;
grant select on public.store_subscriptions to authenticated;

-- store_events: every notification Apple / Google sent, for support and
-- auditing. Service role only (no member access).
create table public.store_events (
  id                     bigint generated always as identity primary key,
  platform               text not null check (platform in ('apple', 'google')),
  notification_type      text,
  subtype                text,
  store_subscription_id  text,
  outcome                text not null,
  payload                jsonb not null default '{}'::jsonb,
  received_at            timestamptz not null default now()
);

create index store_events_subscription_idx
  on public.store_events (platform, store_subscription_id);

comment on table public.store_events is
  'Log of App Store / Google Play server notifications. Service role only.';

alter table public.store_events enable row level security;
revoke all on public.store_events from anon, authenticated;

-- The signed-in member's membership: their best subscription (one with access
-- first, then the latest expiry). No row = never subscribed.
create function public.get_my_membership()
returns table (
  is_member    boolean,
  platform     text,
  product_id   text,
  plan_id      text,
  status       text,
  expires_at   timestamptz,
  auto_renew   boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
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
$$;

revoke all on function public.get_my_membership() from public, anon;
grant execute on function public.get_my_membership() to authenticated;
