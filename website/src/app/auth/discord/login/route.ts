import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';

import { authorizeUrl } from '@/lib/discord';
import { discordConfigured } from '@/lib/config';
import { cookieOptions } from '@/lib/session';

/**
 * Start LOGGING IN with a Discord account.
 *
 * Companion to `/auth/discord/connect` (which ATTACHES Discord to a session
 * that already exists). This route is for visitors who do not have a portal
 * session yet and want to use their Discord account as a credential: the
 * callback looks up the Discord ID and signs the matching portal account in.
 *
 * There is no link flow here — anonymous visitors get the login, signed-in
 * visitors get the link. Mixing them would let anybody with a Discord
 * browser session silently bind that account to whatever email the cookie
 * names, which is the same hazard `/auth/discord/connect` was built to prevent.
 *
 * The state cookie carries the literal string `/auth/discord/login`. The
 * callback reads it as the signal that this is the login flow, not the
 * attach flow.
 */
export async function GET(request: Request) {
  if (!discordConfigured) {
    return NextResponse.redirect(
      new URL('/login?error=discord-not-configured', request.url),
    );
  }

  const redirect = NextResponse.redirect(authorizeUrl('/auth/discord/login'));
  redirect.cookies.set('nifty_oauth_state', '/auth/discord/login', cookieOptions());
  return redirect;
}
