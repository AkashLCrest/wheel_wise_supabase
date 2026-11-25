// deno-lint-ignore-file no-explicit-any -- raw JSON from Apple / Google / the app
// apple-notifications: App Store Server Notifications V2 (renewals,
// cancellations, billing problems, refunds, expiry).
//
// Set in App Store Connect → App → App Information → App Store Server
// Notifications (production and sandbox URL, Version 2):
//   https://<project>.supabase.co/functions/v1/apple-notifications?secret=<STORE_WEBHOOK_SECRET>
//
// verify_jwt is off (Apple doesn't send a Supabase session). The notification
// is only used to learn WHICH subscription changed; its current state is then
// read from the App Store Server API, so a forged notification can't grant or
// change anything.
//
// Replies 200 once handled (or deliberately ignored); 500 makes Apple retry.
import { fetchAppleSubscription } from '../_shared/apple.ts';
import { logEvent, saveFromNotification } from '../_shared/db.ts';
import { StoreNotFoundError, WrongProductError } from '../_shared/types.ts';
import {
  decodeJwsPayload,
  hasWebhookSecret,
  json,
  requireEnv,
} from '../_shared/util.ts';

Deno.serve(async req => {
  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }
  if (!hasWebhookSecret(req)) {
    return json({ error: 'unauthorized' }, 401);
  }

  let notification: any;
  try {
    const body = await req.json();
    notification = decodeJwsPayload(body.signedPayload);
  } catch {
    return json({ error: 'invalid_body' }, 400);
  }

  const type: string | null = notification.notificationType ?? null;
  const subtype: string | null = notification.subtype ?? null;
  const data = notification.data ?? {};
  const signedTransaction: string | undefined = data.signedTransactionInfo;

  if (data.bundleId && data.bundleId !== requireEnv('APPLE_BUNDLE_ID')) {
    await logEvent({ platform: 'apple', notificationType: type, subtype, outcome: 'ignored_other_app', payload: notification });
    return json({ ok: true });
  }
  if (!signedTransaction) {
    // TEST notifications and summaries carry no transaction.
    await logEvent({ platform: 'apple', notificationType: type, subtype, outcome: 'no_transaction', payload: notification });
    return json({ ok: true });
  }

  let transaction: any = {};
  try {
    transaction = decodeJwsPayload(signedTransaction);
    const subscription = await fetchAppleSubscription(String(transaction.transactionId));
    const owner = await saveFromNotification(subscription);
    await logEvent({
      platform: 'apple',
      notificationType: type,
      subtype,
      storeSubscriptionId: subscription.storeSubscriptionId,
      outcome: owner ? `saved:${subscription.status}` : 'no_account',
      payload: { notification, transaction },
    });
    return json({ ok: true });
  } catch (error) {
    if (error instanceof StoreNotFoundError || error instanceof WrongProductError) {
      await logEvent({
        platform: 'apple',
        notificationType: type,
        subtype,
        storeSubscriptionId: transaction.originalTransactionId ?? null,
        outcome: error instanceof StoreNotFoundError ? 'not_found' : 'wrong_product',
        payload: { notification, transaction },
      });
      return json({ ok: true });
    }
    console.error('apple-notifications failed', error);
    await logEvent({
      platform: 'apple',
      notificationType: type,
      subtype,
      storeSubscriptionId: transaction.originalTransactionId ?? null,
      outcome: 'error',
      payload: { notification, transaction, error: String(error) },
    });
    return json({ error: 'server_error' }, 500);
  }
});
