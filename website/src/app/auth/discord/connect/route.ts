import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';

import { authorizeUrl } from '@/lib/discord';
import { discordConfigured } from '@/lib/config';
import { decodeSession } from '@/lib/session';
import { cookieOptions } from '@/lib/session';

/**
 * Start ATTACHING a Discord account.
 *
 * This is not a login and must never become one. There is exactly one difference
 * from the old `/auth/login`, and it is the whole point: a portal session has to
 * already exist. Without that check the route would let anybody who has a Discord
 * browser session attach that Discord account to whatever portal account the
 * cookie names — which is fine, but it would also be reachable with no portal
 * account at all, and then the callback would have nothing to attach TO.
 *
 * The state cookie carries the return path and is compared byte for byte in the
 * callback, so it doubles as the CSRF token. Only this route writes it.
 */
export async function GET(request: Request) {
  const store = await cookies();

  if (!decodeSession(store.get('nifty_session')?.value)) {
    return NextResponse.redirect(new URL('/login?error=link-needs-account', request.url));
  }

  if (!discordConfigured) {
    return NextResponse.redirect(new URL('/account?error=discord-not-configured', request.url));
  }

  const url = new URL(request.url);

  // Same-site paths only. An absolute URL here would survive into the redirect
  // back from Discord, because the callback reuses this value as the destination.
  const requested = url.searchParams.get('next');
  const next =
    requested && requested.startsWith('/') && !requested.startsWith('//') ? requested : '/account';

  const redirect = NextResponse.redirect(authorizeUrl(next));
  redirect.cookies.set('nifty_oauth_state', next, cookieOptions());
  return redirect;
}