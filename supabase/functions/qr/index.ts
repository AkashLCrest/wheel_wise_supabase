// qr: the address printed in the WHEEL WISE™ booklet's QR codes (B22).
//
//   GET .../functions/v1/qr?c=<code>
//
// Looks the code up in `qr_links` and redirects:
//   target is a web address (https://...)  → that address
//   target is an app screen (e.g. Wheel)   → wheelwise://qr/<code>, which
//                                             opens the app on that screen
// The printed QR never changes; the team repoints it by editing the row's
// `target` in the dashboard (no app release, no reprint). An unknown code
// gets a short "not active yet" page.
//
// Public (verify_jwt off): anyone who scans the booklet can open it.
import { createClient } from 'npm:@supabase/supabase-js@2.118.0';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

const CODE = /^[a-z0-9_-]{1,64}$/;

function notActive(): Response {
  return new Response('This WHEEL WISE link is not active yet.', {
    status: 404,
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
}

Deno.serve(async req => {
  if (req.method !== 'GET') {
    return new Response('Method not allowed', { status: 405 });
  }
  // Trailing punctuation sneaks in when an address is copied from a sentence.
  const code = (new URL(req.url).searchParams.get('c') ?? '')
    .trim()
    .replace(/[.,;:!)'"]+$/, '')
    .toLowerCase();
  if (!CODE.test(code)) {
    return notActive();
  }

  const { data, error } = await supabase
    .from('qr_links')
    .select('target')
    .eq('code', code)
    .maybeSingle();
  if (error) {
    return new Response('Please try again later.', { status: 503 });
  }
  if (!data) {
    return notActive();
  }

  const location = /^https:\/\//i.test(data.target)
    ? data.target
    : `wheelwise://qr/${code}`;
  return new Response(null, { status: 302, headers: { Location: location } });
});
