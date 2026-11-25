// Small helpers shared by the membership edge functions.

/** Reads a required secret; throws (500) when it isn't set. */
export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing secret ${name}`);
  }
  return value;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

const encoder = new TextEncoder();

export function base64UrlEncode(input: string | Uint8Array): string {
  const bytes = typeof input === 'string' ? encoder.encode(input) : input;
  let binary = '';
  bytes.forEach(b => (binary += String.fromCharCode(b)));
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function base64Decode(input: string): string {
  const normal = input.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normal + '='.repeat((4 - (normal.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

/**
 * Payload of a JWS / JWT, WITHOUT checking its signature. Only use it on data
 * fetched directly from Apple's API over HTTPS (already authentic), or to
 * find out which subscription a notification is about before re-reading it
 * from the store.
 */
// deno-lint-ignore no-explicit-any
export function decodeJwsPayload(jws: string): any {
  const part = jws.split('.')[1];
  if (!part) {
    throw new Error('Malformed JWS');
  }
  return JSON.parse(base64Decode(part));
}

/** DER bytes of a PEM private key ("-----BEGIN PRIVATE KEY-----"). */
export function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem
    .replace(/\\n/g, '\n')
    .replace(/-----(BEGIN|END) [A-Z ]+-----/g, '')
    .replace(/\s+/g, '');
  return Uint8Array.from(atob(body), c => c.charCodeAt(0));
}

/** Signs `header.payload` and returns the compact JWT. */
export async function signJwt(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
  key: CryptoKey,
  algorithm: AlgorithmIdentifier | EcdsaParams,
): Promise<string> {
  const input = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(
    JSON.stringify(payload),
  )}`;
  const signature = await crypto.subtle.sign(
    algorithm,
    key,
    encoder.encode(input),
  );
  return `${input}.${base64UrlEncode(new Uint8Array(signature))}`;
}

/** Constant-time string comparison (for the webhook secret). */
export function safeEqual(a: string, b: string): boolean {
  const x = encoder.encode(a);
  const y = encoder.encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return diff === 0;
}

/**
 * Store webhooks are called by Apple / Google, not by a signed-in member, so
 * the URL carries a secret: .../apple-notifications?secret=<STORE_WEBHOOK_SECRET>.
 * (The handlers also never trust the notification body: they re-read the
 * subscription from the store.)
 */
export function hasWebhookSecret(req: Request): boolean {
  const given = new URL(req.url).searchParams.get('secret') ?? '';
  return safeEqual(given, requireEnv('STORE_WEBHOOK_SECRET'));
}

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID.test(value);
}
