// deno-lint-ignore-file no-explicit-any -- raw JSON from Apple / Google / the app
// google-notifications: Google Play Real-time developer notifications
// (renewals, cancellations, holds, refunds, expiry), delivered by a Pub/Sub
// push subscription.
//
// Set up: Play Console → Monetization setup → Real-time developer
// notifications → a Pub/Sub topic, with a push subscription to:
//   https://<project>.supabase.co/functions/v1/google-notifications?secret=<STORE_WEBHOOK_SECRET>
//
// verify_jwt is off (Pub/Sub doesn't send a Supabase session). The message is
// only used to learn WHICH purchase changed; its current state is then read
// from the Google Play Developer API, so a forged message can't grant or
// change anything.
//
// Replies 200 once handled (or deliberately ignored); 500 makes Pub/Sub retry.
import { fetchGoogleSubscription } from '../_shared/google.ts';
import { logEvent, markRevoked, saveFromNotification } from '../_shared/db.ts';
import { StoreNotFoundError, WrongProductError } from '../_shared/types.ts';
import { base64Decode, hasWebhookSecret, json, requireEnv } from '../_shared/util.ts';

// Subscription notification types (Google Play RTDN).
const SUBSCRIPTION_REVOKED = 12;
// voidedPurchaseNotification.productType
const VOIDED_SUBSCRIPTION = 1;

Deno.serve(async req => {
  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }
  if (!hasWebhookSecret(req)) {
    return json({ error: 'unauthorized' }, 401);
  }

  let message: any;
  try {
    const body = await req.json();
    message = JSON.parse(base64Decode(body.message.data));
  } catch {
    return json({ error: 'invalid_body' }, 400);
  }

  if (message.packageName !== requireEnv('GOOGLE_PACKAGE_NAME')) {
    await logEvent({ platform: 'google', outcome: 'ignored_other_app', payload: message });
    return json({ ok: true });
  }

  // Refund / chargeback.
  const voided = message.voidedPurchaseNotification;
  if (voided) {
    const changed =
      voided.productType === VOIDED_SUBSCRIPTION &&
      (await markRevoked('google', voided.purchaseToken));
    await logEvent({
      platform: 'google',
      notificationType: 'VOIDED_PURCHASE',
      storeSubscriptionId: voided.purchaseToken ?? null,
      outcome: changed ? 'revoked' : 'ignored',
      payload: message,
    });
    return json({ ok: true });
  }

  const notice = message.subscriptionNotification;
  if (!notice?.purchaseToken) {
    // testNotification, one-time products.
    await logEvent({
      platform: 'google',
      notificationType: message.testNotification ? 'TEST' : null,
      outcome: 'no_subscription',
      payload: message,
    });
    return json({ ok: true });
  }

  const type = String(notice.notificationType);
  try {
    const subscription = await fetchGoogleSubscription(notice.purchaseToken);
    if (notice.notificationType === SUBSCRIPTION_REVOKED) {
      subscription.status = 'revoked';
    }
    const owner = await saveFromNotification(subscription);
    await logEvent({
      platform: 'google',
      notificationType: type,
      storeSubscriptionId: notice.purchaseToken,
      outcome: owner ? `saved:${subscription.status}` : 'no_account',
      payload: message,
    });
    return json({ ok: true });
  } catch (error) {
    if (error instanceof StoreNotFoundError || error instanceof WrongProductError) {
      await logEvent({
        platform: 'google',
        notificationType: type,
        storeSubscriptionId: notice.purchaseToken,
        outcome: error instanceof StoreNotFoundError ? 'not_found' : 'wrong_product',
        payload: message,
      });
      return json({ ok: true });
    }
    console.error('google-notifications failed', error);
    await logEvent({
      platform: 'google',
      notificationType: type,
      storeSubscriptionId: notice.purchaseToken,
      outcome: 'error',
      payload: { message, error: String(error) },
    });
    return json({ error: 'server_error' }, 500);
  }
});
