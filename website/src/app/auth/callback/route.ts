import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';

import { exchangeCode } from '@/lib/discord';
import { encodeSession, cookieOptions } from '@/lib/session';

/**
 * Discord sends the player back here.
 *
 * Three things have to line up before a session exists: a code, a state that
 * matches the one we issued, and an identity that is actually a Discord ID.
 * Anything else is a failed login, not a partial one.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');

  const store = await cookies();
  const expectedState = store.get('nifty_oauth_state')?.value;

  // A missing or mismatched state means the round trip did not start here.
  if (!code || !state || !expectedState || state !== expectedState) {
    return NextResponse.redirect(new URL('/?error=login-failed', request.url));
  }

  const identity = await exchangeCode(code);
  if (!identity) {
    return NextResponse.redirect(new URL('/?error=login-failed', request.url));
  }

  // Only same-site paths. An attacker-supplied absolute URL here would turn the
  // login into an open redirect carrying a fresh session cookie.
  const destination = state.startsWith('/') && !state.startsWith('//') ? state : '/status';

  const response = NextResponse.redirect(new URL(destination, request.url));
  response.cookies.set(
    'nifty_session',
    encodeSession({
      discordId: identity.id,
      username: identity.username,
      avatar: identity.avatar,
    }),
    cookieOptions(),
  );
  response.cookies.delete('nifty_oauth_state');

  return response;
}