// WHEEL WISE membership products. Must match MEMBERSHIP_PLANS in the app
// (WheelUI src/constants/membership.ts) and the subscription products in
// App Store Connect and Google Play Console (same ids on both stores).

export type PlanId = 'annual' | 'monthly';

export const PLAN_BY_PRODUCT: Record<string, PlanId> = {
  'com.wheelwise.membership.annual': 'annual',
  'com.wheelwise.membership.monthly': 'monthly',
};

export function isMembershipProduct(productId: unknown): productId is string {
  return typeof productId === 'string' && productId in PLAN_BY_PRODUCT;
}
