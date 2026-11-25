// Saving verified subscriptions to public.store_subscriptions (service role).
import { createClient } from 'npm:@supabase/supabase-js@2.118.0';

import { acknowledgeGoogleSubscription } from './google.ts';
import { PLAN_BY_PRODUCT } from './products.ts';
import type { Platform, StoreSubscription } from './types.ts';
import { isUuid, requireEnv } from './util.ts';

export const admin = createClient(
  requireEnv('SUPABASE_URL'),
  requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
  { auth: { persistSession: false, autoRefreshToken: false } },
);

const TABLE = 'store_subscriptions';

function columns(sub: StoreSubscription) {
  return {
    platform: sub.platform,
    store_subscription_id: sub.storeSubscriptionId,
    product_id: sub.productId,
    plan_id: PLAN_BY_PRODUCT[sub.productId] ?? null,
    status: sub.status,
    expires_at: sub.expiresAt,
    auto_renew: sub.autoRenew,
    environment: sub.environment,
    store_data: sub.storeData,
  };
}

async function ownerOf(
  platform: Platform,
  storeSubscriptionId: string,
): Promise<string | null> {
  const { data, error } = await admin
    .from(TABLE)
    .select('user_id')
    .eq('platform', platform)
    .eq('store_subscription_id', storeSubscriptionId)
    .maybeSingle();
  if (error) {
    throw error;
  }
  return data?.user_id ?? null;
}

async function update(sub: StoreSubscription, userId: string): Promise<void> {
  const { error } = await admin
    .from(TABLE)
    .update(columns(sub))
    .eq('platform', sub.platform)
    .eq('store_subscription_id', sub.storeSubscriptionId)
    .eq('user_id', userId);
  if (error) {
    throw error;
  }
}

/** Inserts; returns false if another request saved the same subscription first. */
async function insert(sub: StoreSubscription, userId: string): Promise<boolean> {
  const { error } = await admin
    .from(TABLE)
    .insert({ ...columns(sub), user_id: userId });
  if (error?.code === '23505') {
    return false;
  }
  if (error) {
    throw error;
  }
  return true;
}

/** Google plan change / resubscribe: the older purchase token is replaced. */
async function retireLinkedToken(
  sub: StoreSubscription,
  userId: string,
): Promise<void> {
  if (sub.platform !== 'google' || !sub.linkedPurchaseToken) {
    return;
  }
  const { error } = await admin
    .from(TABLE)
    .update({ status: 'replaced' })
    .eq('platform', 'google')
    .eq('store_subscription_id', sub.linkedPurchaseToken)
    .eq('user_id', userId);
  if (error) {
    throw error;
  }
}

/**
 * Google: acknowledge once linked. Not fatal if it fails (e.g. the app's
 * finishTransaction acknowledged it a moment earlier): the app acknowledges
 * too, and the next notification for this purchase tries again.
 */
async function acknowledgeIfNeeded(sub: StoreSubscription): Promise<void> {
  if (sub.platform !== 'google' || !sub.needsAcknowledge || sub.status === 'pending') {
    return;
  }
  try {
    await acknowledgeGoogleSubscription(sub.productId, sub.storeSubscriptionId);
  } catch (error) {
    console.error('Google acknowledge failed', error);
  }
}

export type LinkResult = 'verified' | 'other_account';

/**
 * Links a verified subscription to the signed-in member and saves it.
 *
 * A subscription belongs to one WHEEL WISE account: the account the app
 * attached to the purchase, or (purchases with no account attached, e.g. an
 * App Store offer code) the first account to verify it. Anyone else gets
 * 'other_account' and no access.
 */
export async function linkToUser(
  sub: StoreSubscription,
  userId: string,
): Promise<LinkResult> {
  if (sub.accountToken && sub.accountToken.toLowerCase() !== userId.toLowerCase()) {
    return 'other_account';
  }
  for (let attempt = 0; attempt < 2; attempt++) {
    const owner = await ownerOf(sub.platform, sub.storeSubscriptionId);
    if (owner && owner !== userId) {
      return 'other_account';
    }
    if (owner) {
      await update(sub, userId);
    } else if (!(await insert(sub, userId))) {
      continue; // saved by a parallel request: check the owner again
    }
    await retireLinkedToken(sub, userId);
    await acknowledgeIfNeeded(sub);
    return 'verified';
  }
  return 'other_account';
}

async function userExists(userId: string): Promise<boolean> {
  const { data, error } = await admin.auth.admin.getUserById(userId);
  return !error && Boolean(data?.user);
}

/**
 * Store notification: updates the saved subscription. A subscription the app
 * never got to verify (e.g. the app closed mid-purchase) is saved for the
 * account attached to the purchase, if that account exists.
 * Returns the owning user id, or null when it can't be linked to anyone.
 */
export async function saveFromNotification(
  sub: StoreSubscription,
): Promise<string | null> {
  const owner = await ownerOf(sub.platform, sub.storeSubscriptionId);
  if (owner) {
    await update(sub, owner);
    await retireLinkedToken(sub, owner);
    await acknowledgeIfNeeded(sub);
    return owner;
  }
  if (isUuid(sub.accountToken) && (await userExists(sub.accountToken))) {
    return (await linkToUser(sub, sub.accountToken)) === 'verified'
      ? sub.accountToken
      : null;
  }
  return null;
}

/** Marks a saved subscription as refunded / revoked. */
export async function markRevoked(
  platform: Platform,
  storeSubscriptionId: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from(TABLE)
    .update({ status: 'revoked' })
    .eq('platform', platform)
    .eq('store_subscription_id', storeSubscriptionId)
    .select('id');
  if (error) {
    throw error;
  }
  return (data ?? []).length > 0;
}

export async function logEvent(event: {
  platform: Platform;
  notificationType?: string | null;
  subtype?: string | null;
  storeSubscriptionId?: string | null;
  outcome: string;
  payload: unknown;
}): Promise<void> {
  const { error } = await admin.from('store_events').insert({
    platform: event.platform,
    notification_type: event.notificationType ?? null,
    subtype: event.subtype ?? null,
    store_subscription_id: event.storeSubscriptionId ?? null,
    outcome: event.outcome,
    payload: event.payload ?? {},
  });
  if (error) {
    console.error('store_events insert failed', error);
  }
}
