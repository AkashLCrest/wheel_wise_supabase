// deno-lint-ignore-file no-explicit-any -- raw JSON from Apple / Google / the app
// App Store Server API: reads a subscription's current state straight from
// Apple, authenticated with the team's In-App Purchase key.
//
// Secrets:
//   APPLE_ISSUER_ID    App Store Connect → Users and Access → Integrations → In-App Purchase (Issuer ID)
//   APPLE_KEY_ID       the In-App Purchase key's id
//   APPLE_PRIVATE_KEY  contents of the downloaded SubscriptionKey_<id>.p8
//   APPLE_BUNDLE_ID    the iOS app's bundle id
//
// Responses come over HTTPS from Apple's own API in reply to our signed
// request, so the signed transaction / renewal info inside them is decoded
// directly.
import { isMembershipProduct } from './products.ts';
import {
  type StoreSubscription,
  StoreNotFoundError,
  type SubscriptionStatus,
  WrongProductError,
} from './types.ts';
import { decodeJwsPayload, pemToDer, requireEnv, signJwt } from './util.ts';

const PRODUCTION = 'https://api.storekit.itunes.apple.com';
const SANDBOX = 'https://api.storekit-sandbox.itunes.apple.com';

let signingKey: Promise<CryptoKey> | null = null;

function key(): Promise<CryptoKey> {
  signingKey ??= crypto.subtle.importKey(
    'pkcs8',
    pemToDer(requireEnv('APPLE_PRIVATE_KEY')),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
  return signingKey;
}

async function bearerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  return signJwt(
    { alg: 'ES256', kid: requireEnv('APPLE_KEY_ID'), typ: 'JWT' },
    {
      iss: requireEnv('APPLE_ISSUER_ID'),
      iat: now,
      exp: now + 600,
      aud: 'appstoreconnect-v1',
      bid: requireEnv('APPLE_BUNDLE_ID'),
    },
    await key(),
    { name: 'ECDSA', hash: 'SHA-256' },
  );
}

type AppleResponse = { body: any; base: string };

async function get(base: string, path: string): Promise<Response> {
  return fetch(`${base}${path}`, {
    headers: { Authorization: `Bearer ${await bearerToken()}` },
  });
}

/**
 * Apple's advice: ask production first; a 404 means the transaction belongs
 * to the sandbox (TestFlight, App Review, sandbox testers), so ask there.
 */
async function getAnyEnvironment(path: string): Promise<AppleResponse> {
  for (const base of [PRODUCTION, SANDBOX]) {
    const res = await get(base, path);
    if (res.ok) {
      return { body: await res.json(), base };
    }
    if (res.status !== 404) {
      throw new Error(`App Store API ${res.status}: ${await res.text()}`);
    }
  }
  throw new StoreNotFoundError('Transaction not found');
}

async function getIn(base: string, path: string): Promise<any> {
  const res = await get(base, path);
  if (res.status === 404) {
    throw new StoreNotFoundError('Subscription not found');
  }
  if (!res.ok) {
    throw new Error(`App Store API ${res.status}: ${await res.text()}`);
  }
  return res.json();
}

// Apple subscription status codes.
const STATUS: Record<number, SubscriptionStatus> = {
  1: 'active',
  2: 'expired',
  3: 'billing_retry',
  4: 'grace_period',
  5: 'revoked',
};

function iso(ms: unknown): string | null {
  return typeof ms === 'number' ? new Date(ms).toISOString() : null;
}

/** Current state of the subscription that `transactionId` belongs to. */
export async function fetchAppleSubscription(
  transactionId: string,
): Promise<StoreSubscription> {
  const found = await getAnyEnvironment(
    `/inApps/v1/transactions/${encodeURIComponent(transactionId)}`,
  );
  const transaction = decodeJwsPayload(found.body.signedTransactionInfo);
  if (transaction.bundleId !== requireEnv('APPLE_BUNDLE_ID')) {
    throw new WrongProductError('Transaction is for another app');
  }
  if (!isMembershipProduct(transaction.productId)) {
    throw new WrongProductError('Not a membership product');
  }
  const original: string = transaction.originalTransactionId;

  // Latest transaction + renewal info for this subscription.
  const statuses = await getIn(
    found.base,
    `/inApps/v1/subscriptions/${encodeURIComponent(original)}`,
  );
  let entry: any = null;
  for (const group of statuses.data ?? []) {
    for (const item of group.lastTransactions ?? []) {
      if (item.originalTransactionId === original) {
        entry = item;
      }
    }
  }
  if (!entry) {
    throw new StoreNotFoundError('Subscription not found');
  }
  const latest = decodeJwsPayload(entry.signedTransactionInfo);
  const renewal = entry.signedRenewalInfo
    ? decodeJwsPayload(entry.signedRenewalInfo)
    : {};

  let status: SubscriptionStatus = STATUS[entry.status] ?? 'expired';
  if (latest.revocationDate) {
    status = 'revoked';
  }
  const expiresAt =
    status === 'grace_period' && renewal.gracePeriodExpiresDate
      ? iso(renewal.gracePeriodExpiresDate)
      : iso(latest.expiresDate);

  return {
    platform: 'apple',
    storeSubscriptionId: original,
    productId: isMembershipProduct(latest.productId)
      ? latest.productId
      : transaction.productId,
    status,
    expiresAt,
    autoRenew: renewal.autoRenewStatus === 1,
    environment: latest.environment === 'Sandbox' ? 'sandbox' : 'production',
    accountToken: latest.appAccountToken ?? transaction.appAccountToken ?? null,
    storeData: { transaction: latest, renewal, appleStatus: entry.status },
  };
}
