// deno-lint-ignore-file no-explicit-any -- raw JSON from Apple / Google / the app
// Google Play Developer API: reads a subscription purchase straight from
// Google and acknowledges it.
//
// Secrets:
//   GOOGLE_SERVICE_ACCOUNT_JSON  key file of a Google Cloud service account that
//                                has been given access in Play Console → Users
//                                and permissions (View financial data, Manage
//                                orders and subscriptions)
//   GOOGLE_PACKAGE_NAME          the Android application id
import { isMembershipProduct } from './products.ts';
import {
  type StoreSubscription,
  StoreNotFoundError,
  type SubscriptionStatus,
  WrongProductError,
} from './types.ts';
import { pemToDer, requireEnv, signJwt } from './util.ts';

const API = 'https://androidpublisher.googleapis.com/androidpublisher/v3';
const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';

let cachedToken: { value: string; expiresAt: number } | null = null;

async function accessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) {
    return cachedToken.value;
  }
  const account = JSON.parse(requireEnv('GOOGLE_SERVICE_ACCOUNT_JSON'));
  const tokenUri: string =
    account.token_uri ?? 'https://oauth2.googleapis.com/token';
  const signingKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt(
    { alg: 'RS256', typ: 'JWT' },
    {
      iss: account.client_email,
      scope: SCOPE,
      aud: tokenUri,
      iat: now,
      exp: now + 3600,
    },
    signingKey,
    { name: 'RSASSA-PKCS1-v1_5' },
  );
  const res = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!res.ok) {
    throw new Error(`Google OAuth ${res.status}: ${await res.text()}`);
  }
  const body = await res.json();
  cachedToken = {
    value: body.access_token,
    expiresAt: Date.now() + body.expires_in * 1000,
  };
  return cachedToken.value;
}

function packageName(): string {
  return requireEnv('GOOGLE_PACKAGE_NAME');
}

function mapStatus(state: string, expiresAt: string | null): SubscriptionStatus {
  switch (state) {
    case 'SUBSCRIPTION_STATE_ACTIVE':
      return 'active';
    case 'SUBSCRIPTION_STATE_CANCELED':
      // Auto-renew turned off: access continues until the paid period ends.
      return expiresAt && Date.parse(expiresAt) > Date.now()
        ? 'active'
        : 'expired';
    case 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD':
      return 'grace_period';
    case 'SUBSCRIPTION_STATE_ON_HOLD':
      return 'on_hold';
    case 'SUBSCRIPTION_STATE_PAUSED':
      return 'paused';
    case 'SUBSCRIPTION_STATE_PENDING':
      return 'pending';
    default:
      // EXPIRED, PENDING_PURCHASE_CANCELED, unknown
      return 'expired';
  }
}

/** Current state of the subscription with this purchase token. */
export async function fetchGoogleSubscription(
  purchaseToken: string,
): Promise<StoreSubscription> {
  const res = await fetch(
    `${API}/applications/${packageName()}/purchases/subscriptionsv2/tokens/${encodeURIComponent(
      purchaseToken,
    )}`,
    { headers: { Authorization: `Bearer ${await accessToken()}` } },
  );
  if (res.status === 404 || res.status === 410 || res.status === 400) {
    throw new StoreNotFoundError('Purchase token not found');
  }
  if (!res.ok) {
    throw new Error(`Google Play API ${res.status}: ${await res.text()}`);
  }
  const body = await res.json();
  const item = (body.lineItems ?? []).find((line: any) =>
    isMembershipProduct(line.productId),
  );
  if (!item) {
    throw new WrongProductError('Not a membership product');
  }
  const expiresAt: string | null = item.expiryTime ?? null;
  return {
    platform: 'google',
    storeSubscriptionId: purchaseToken,
    productId: item.productId,
    status: mapStatus(body.subscriptionState, expiresAt),
    expiresAt,
    autoRenew: item.autoRenewingPlan?.autoRenewEnabled === true,
    environment: body.testPurchase ? 'sandbox' : 'production',
    accountToken:
      body.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
    storeData: body,
    linkedPurchaseToken: body.linkedPurchaseToken ?? null,
    needsAcknowledge:
      body.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING',
  };
}

/**
 * Acknowledges the purchase. Google refunds subscriptions that aren't
 * acknowledged within 3 days, so the server does this as soon as the purchase
 * is linked to an account (the app's finishTransaction does it too; either
 * is enough).
 */
export async function acknowledgeGoogleSubscription(
  productId: string,
  purchaseToken: string,
): Promise<void> {
  const res = await fetch(
    `${API}/applications/${packageName()}/purchases/subscriptions/${encodeURIComponent(
      productId,
    )}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${await accessToken()}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
    },
  );
  if (!res.ok) {
    throw new Error(`Google acknowledge ${res.status}: ${await res.text()}`);
  }
}
