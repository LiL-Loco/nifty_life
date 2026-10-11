import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';

import { authorizeUrl, devIdentity } from '@/lib/discord';
import { loginMode } from '@/lib/config';
import { encodeSession, cookieOptions } from '@/lib/session';

/**
 * Start a login.
 *
 * Discord first, when it is configured. The development login exists only so the
 * site can be built before an application exists, and `config.ts` has already
 * refused to boot with it enabled in production.
 */
export async function GET(request: Request) {
  const mode = loginMode();

  if (mode === 'discord') {
    const url = new URL(request.url);
    const state = url.searchParams.get('next') ?? '/status';

    // The state carries the post-login destination only. It is echoed back and
    // sanity-checked in the callback, so it cannot be used to redirect anywhere
    // outside this site.
    const redirect = NextResponse.redirect(authorizeUrl(state));
    redirect.cookies.set('nifty_oauth_state', state, cookieOptions());
    return redirect;
  }

  if (mode === 'dev') {
    const identity = devIdentity();
    if (!identity) {
      return NextResponse.redirect(
        new URL('/?error=dev-auth-not-configured', request.url),
      );
    }

    const response = NextResponse.redirect(new URL('/status', request.url));
    response.cookies.set(
      'nifty_session',
      encodeSession({
        discordId: identity.id,
        username: identity.username,
        avatar: identity.avatar,
      }),
      cookieOptions(),
    );
    return response;
  }

  return NextResponse.redirect(new URL('/?error=login-unavailable', request.url));
}