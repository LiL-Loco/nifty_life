import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';

import { exchangeCode } from '@/lib/discord';
import { linkDiscord } from '@/lib/users';
import { decodeSession } from '@/lib/session';

/**
 * Discord sends the person back here after they approved the attach.
 *
 * Four things have to line up before a link is written: a code, a state that
 * matches the one this server issued, a signed-in portal session, and an identity
 * that is actually a Discord ID. Anything else is a failed attach, not a partial
 * one — in particular NO session is created here. Signing in is email and
 * password, on /login, and a Discord account that gets attached does not change
 * who is signed in.
 *
 * The session requirement is what makes the link worth anything: you must already
 * be authenticated as the portal account you are attaching to, and you must prove
 * you hold the Discord account being attached. `portal_user_discord` is UNIQUE in
 * both directions, so the database refuses the two dishonest cases — claiming
 * somebody else's Discord identity, and holding two portal accounts to apply
 * twice.
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

  const session = decodeSession(store.get('nifty_session')?.value);
  if (!session) {
    return NextResponse.redirect(new URL('/login?error=link-needs-account', request.url));
  }

  const identity = await exchangeCode(code);
  if (!identity) {
    return NextResponse.redirect(new URL('/account?error=link-failed', request.url));
  }

  const result = await linkDiscord(session.userId, identity.id, identity.username);

  // Only same-site paths, and only from the state cookie this server wrote.
  const destination = state.startsWith('/') && !state.startsWith('//') ? state : '/account';

  const suffix = result.ok ? '?linked=1' : `?error=${result.code}`;
  const response = NextResponse.redirect(new URL(`${destination}${suffix}`, request.url));
  response.cookies.delete('nifty_oauth_state');

  return response;
}