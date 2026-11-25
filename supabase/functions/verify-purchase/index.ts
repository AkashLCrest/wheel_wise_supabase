// deno-lint-ignore-file no-explicit-any -- raw JSON from Apple / Google / the app
// verify-purchase: the app sends every membership purchase (and every
// purchase found by "Restore purchases") here. The purchase is checked with
// Apple / Google and linked to the signed-in member's account.
//
// Called with the member's session (verify_jwt on).
// Body: { platform: 'apple', transactionId }
//     | { platform: 'google', productId, purchaseToken }
// Reply (200): { result: 'verified' | 'other_account' | 'not_found' | 'wrong_product' }
//   verified       linked to this account; the app re-reads get_my_membership()
//   other_account  the purchase belongs to a different WHEEL WISE account
//   not_found      the store doesn't know this purchase
//   wrong_product  not a WHEEL WISE membership
// The app finishes the store transaction only after 'verified' or
// 'other_account', so anything else is retried on the next launch.
import { admin, linkToUser } from '../_shared/db.ts';
import { fetchAppleSubscription } from '../_shared/apple.ts';
import { fetchGoogleSubscription } from '../_shared/google.ts';
import { isMembershipProduct } from '../_shared/products.ts';
import { StoreNotFoundError, WrongProductError } from '../_shared/types.ts';
import { json } from '../_shared/util.ts';

Deno.serve(async req => {
  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  const jwt = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
  const { data: auth } = jwt
    ? await admin.auth.getUser(jwt)
    : { data: { user: null } };
  const userId = auth?.user?.id;
  if (!userId) {
    return json({ error: 'unauthorized' }, 401);
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid_body' }, 400);
  }

  try {
    let subscription;
    if (
      body?.platform === 'apple' &&
      typeof body.transactionId === 'string' &&
      /^\d{1,32}$/.test(body.transactionId)
    ) {
      subscription = await fetchAppleSubscription(body.transactionId);
    } else if (
      body?.platform === 'google' &&
      isMembershipProduct(body.productId) &&
      typeof body.purchaseToken === 'string' &&
      body.purchaseToken.length > 0 &&
      body.purchaseToken.length <= 4096
    ) {
      subscription = await fetchGoogleSubscription(body.purchaseToken);
    } else {
      return json({ error: 'invalid_body' }, 400);
    }

    const result = await linkToUser(subscription, userId);
    return json({ result });
  } catch (error) {
    if (error instanceof StoreNotFoundError) {
      return json({ result: 'not_found' });
    }
    if (error instanceof WrongProductError) {
      return json({ result: 'wrong_product' });
    }
    console.error('verify-purchase failed', error);
    return json({ error: 'server_error' }, 500);
  }
});
