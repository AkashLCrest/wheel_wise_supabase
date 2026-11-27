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

type SavedRow = { user_id: string; status: string; expires_at: string | null };

async function findRow(
  platform: Platform,
  storeSubscriptionId: string,
): Promise<SavedRow | null> {
  const { data, error } = await admin
    .from(TABLE)
    .select('user_id, status, expires_at')
    .eq('platform', platform)
    .eq('store_subscription_id', storeSubscriptionId)
    .maybeSingle();
  if (error) {
    throw error;
  }
  return data;
}

function sameUser(a: string | null, b: string): boolean {
  return Boolean(a) && a!.toLowerCase() === b.toLowerCase();
}

/**
 * Whether the saved row still holds the subscription for its owner: paid up or
 * in grace (period not over yet), or the store is still retrying the renewal
 * payment. A lapsed row (expired, refunded, period over) no longer does.
 */
function stillInUse(row: SavedRow): boolean {
  if (row.status === 'billing_retry') {
    return true;
  }
  return (
    (row.status === 'active' || row.status === 'grace_period') &&
    row.expires_at !== null &&
    Date.parse(row.expires_at) > Date.now()
  );
}

/**
 * Apple keeps the same originalTransactionId when an Apple ID subscribes again
 * after the subscription ended, even from another WHEEL WISE account. The
 * subscription may move to that account only when the old owner's row has
 * lapsed AND the new purchase carries the new account's id (appAccountToken),
 * i.e. the new account made (and pays for) it.
 */
function mayTakeOver(row: SavedRow, sub: StoreSubscription, userId: string): boolean {
  return !stillInUse(row) && sameUser(sub.accountToken, userId);
}

/**
 * Saves the store's current state on the row owned by `owner`, and moves the
 * row to `newOwner` when given (lapsed subscription taken over). Returns false
 * when the row no longer belongs to `owner` (changed by a parallel request).
 */
async function update(
  sub: StoreSubscription,
  owner: string,
  newOwner?: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from(TABLE)
    .update(newOwner ? { ...columns(sub), user_id: newOwner } : columns(sub))
    .eq('platform', sub.platform)
    .eq('store_subscription_id', sub.storeSubscriptionId)
    .eq('user_id', owner)
    .select('id');
  if (error) {
    throw error;
  }
  const saved = (data ?? []).length > 0;
  if (newOwner && saved) {
    console.log(
      `${sub.platform} subscription ${sub.storeSubscriptionId} moved from lapsed account ${owner} to ${newOwner}`,
    );
  }
  return saved;
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

/**
 * Google plan change / resubscribe: the older purchase token is replaced. Google
 * itself says the old token is no longer valid, so its row is retired whoever
 * owns it (it may be another account on the same Google account whose
 * subscription lapsed).
 */
async function retireLinkedToken(sub: StoreSubscription): Promise<void> {
  if (sub.platform !== 'google' || !sub.linkedPurchaseToken) {
    return;
  }
  const { error } = await admin
    .from(TABLE)
    .update({ status: 'replaced' })
    .eq('platform', 'google')
    .eq('store_subscription_id', sub.linkedPurchaseToken);
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

async function afterSave(sub: StoreSubscription): Promise<void> {
  await retireLinkedToken(sub);
  await acknowledgeIfNeeded(sub);
}

/**
 * Links a verified subscription to the signed-in member and saves it.
 *
 * A subscription belongs to one WHEEL WISE account: the account the app
 * attached to the purchase, or (purchases with no account attached, e.g. an
 * App Store offer code) the first account to verify it. Anyone else gets
 * 'other_account' and no access, except when the other account's
 * subscription has lapsed and this member bought it again (mayTakeOver).
 */
export async function linkToUser(
  sub: StoreSubscription,
  userId: string,
): Promise<LinkResult> {
  if (sub.accountToken && !sameUser(sub.accountToken, userId)) {
    return 'other_account';
  }
  for (let attempt = 0; attempt < 2; attempt++) {
    const row = await findRow(sub.platform, sub.storeSubscriptionId);
    let saved: boolean;
    if (!row) {
      saved = await insert(sub, userId);
    } else if (row.user_id === userId) {
      saved = await update(sub, userId);
    } else if (mayTakeOver(row, sub, userId)) {
      saved = await update(sub, row.user_id, userId);
    } else {
      return 'other_account';
    }
    if (saved) {
      await afterSave(sub);
      return 'verified';
    }
    // Changed by a parallel request: check the owner again.
  }
  return 'other_account';
}

async function userExists(userId: string): Promise<boolean> {
  const { data, error } = await admin.auth.admin.getUserById(userId);
  return !error && Boolean(data?.user);
}

/** The account the purchase names (appAccountToken / obfuscatedAccountId), if it exists. */
async function tokenUser(sub: StoreSubscription): Promise<string | null> {
  return isUuid(sub.accountToken) && (await userExists(sub.accountToken))
    ? sub.accountToken.toLowerCase()
    : null;
}

/**
 * Store notification: updates the saved subscription. Returns the owning user
 * id, or null when it can't be linked to anyone.
 *
 * - Saved already: updated for its owner, or moved to the account named in
 *   the purchase when the owner's subscription lapsed and that account bought
 *   it again (Apple resubscribe from another WHEEL WISE account).
 * - Not saved yet (e.g. the app closed mid-purchase): saved for the account
 *   named in the purchase, or (Google resubscribe / plan change made in the
 *   Play Store, which names no account) for the owner of the purchase it
 *   replaces.
 */
export async function saveFromNotification(
  sub: StoreSubscription,
): Promise<string | null> {
  let row = await findRow(sub.platform, sub.storeSubscriptionId);
  for (let attempt = 0; row && attempt < 2; attempt++) {
    const named = sameUser(sub.accountToken, row.user_id) ? null : await tokenUser(sub);
    const owner = named && mayTakeOver(row, sub, named) ? named : row.user_id;
    if (await update(sub, row.user_id, owner === row.user_id ? undefined : owner)) {
      await afterSave(sub);
      return owner;
    }
    row = await findRow(sub.platform, sub.storeSubscriptionId);
  }
  if (row) {
    // Changed by parallel requests both times: fail so the store retries.
    throw new Error('Subscription changed while saving');
  }

  const named = await tokenUser(sub);
  if (named) {
    return (await linkToUser(sub, named)) === 'verified' ? named : null;
  }
  if (sub.platform === 'google' && sub.linkedPurchaseToken) {
    const replaced = await findRow('google', sub.linkedPurchaseToken);
    if (replaced) {
      return (await linkToUser(sub, replaced.user_id)) === 'verified'
        ? replaced.user_id
        : null;
    }
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
