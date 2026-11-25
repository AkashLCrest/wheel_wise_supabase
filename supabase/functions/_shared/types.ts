// The store-independent shape of one subscription, as saved in
// public.store_subscriptions.

export type Platform = 'apple' | 'google';

export type SubscriptionStatus =
  | 'active'
  | 'grace_period'
  | 'billing_retry'
  | 'on_hold'
  | 'paused'
  | 'pending'
  | 'expired'
  | 'revoked'
  | 'replaced';

export type StoreSubscription = {
  platform: Platform;
  /** Apple originalTransactionId, or the Google purchase token. */
  storeSubscriptionId: string;
  productId: string;
  status: SubscriptionStatus;
  expiresAt: string | null;
  autoRenew: boolean;
  environment: 'production' | 'sandbox';
  /**
   * The WHEEL WISE user id the app attached to the purchase (Apple
   * appAccountToken / Google obfuscatedExternalAccountId), if any.
   */
  accountToken: string | null;
  storeData: Record<string, unknown>;
  /** Google: older purchase token this one replaces (plan change / resubscribe). */
  linkedPurchaseToken?: string | null;
  /** Google: purchase still has to be acknowledged (else Google refunds it). */
  needsAcknowledge?: boolean;
};

/** Thrown when the store doesn't know the transaction / token. */
export class StoreNotFoundError extends Error {}

/** The product isn't a WHEEL WISE membership, or is for another app. */
export class WrongProductError extends Error {}
