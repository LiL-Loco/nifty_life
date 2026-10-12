import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';

import { exchangeCode } from '@/lib/discord';
import { linkDiscord, findUserByDiscordId } from '@/lib/users';
import { decodeSession, encodeSession, cookieOptions, SESSION_COOKIE } from '@/lib/session';

/**
 * Discord sends the person back here after they approved the round trip.
 *
 * Two flows share this route, distinguished by the state cookie written by
 * the start route:
 *
 *   - state = a same-site path      → ATTACH. A portal session must already
 *     exist; the Discord account is linked to it.
 *   - state = `/auth/discord/login` → LOG IN. No session needed; the
 *     callback looks up the Discord ID and signs the matching portal
 *     account in.
 *
 * Both paths require a valid code, a state that matches the cookie, and an
 * identity that is actually a Discord ID. Anything else is a refused round
 * trip — no partial links, no partial sessions.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');

  const store = await cookies();
  const expectedState = store.get('nifty_oauth_state')?.value;

  // A missing or mismatched state means the round trip did not start here.
  if (!code || !state || !expectedState || state !== expectedState) {
    return NextResponse.redirect(new URL('/account?error=link-failed', request.url));
  }

  const identity = await exchangeCode(code);
  if (!identity) {
    return NextResponse.redirect(
      new URL(`/${state === '/auth/discord/login' ? 'login' : 'account'}?error=link-failed`, request.url),
    );
  }

  // ---- LOG IN -----------------------------------------------------------
  if (state === '/auth/discord/login') {
    let account;
    try {
      account = await findUserByDiscordId(identity.id);
    } catch (error) {
      // The database is unreachable. Next's 500 tells the visitor nothing and
      // buries the cause in a place nobody reads, so the round trip is refused
      // with the message every other failure gets and the real error is written
      // where it can be found. The retry is genuine advice: the database
      // usually comes back on its own.
      console.error('Discord login: account lookup failed', error);
      return NextResponse.redirect(new URL('/login?error=link-failed', request.url));
    }

    if (!account) {
      return NextResponse.redirect(
        new URL('/login?error=no-account-for-discord', request.url),
      );
    }

    const response = NextResponse.redirect(new URL('/account', request.url));
    response.cookies.set(
      SESSION_COOKIE,
      encodeSession({ userId: account.userId, email: account.email }),
      cookieOptions(),
    );
    response.cookies.delete('nifty_oauth_state');
    return response;
  }

  // ---- ATTACH -----------------------------------------------------------
  const session = decodeSession(store.get(SESSION_COOKIE)?.value);
  if (!session) {
    return NextResponse.redirect(new URL('/login?error=link-needs-account', request.url));
  }

  let result;
  try {
    result = await linkDiscord(session.userId, identity.id, identity.username);
  } catch (error) {
    // Same reasoning as the login branch above: an unreachable database is a
    // failed round trip, not a bug in the page the visitor is looking at.
    console.error('Discord attach: link failed', error);
    return NextResponse.redirect(new URL('/account?error=link-failed', request.url));
  }

  // Only same-site paths, and only from the state cookie this server wrote.
  const destination = state.startsWith('/') && !state.startsWith('//') ? state : '/account';

  const suffix = result.ok ? '?linked=1' : `?error=${result.code}`;
  const response = NextResponse.redirect(new URL(`${destination}${suffix}`, request.url));
  response.cookies.delete('nifty_oauth_state');

  return response;
}
