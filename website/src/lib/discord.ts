/**
 * Discord OAuth (ADR-0007, revised 2026-10-11).
 *
 * Discord is NO LONGER THE LOGIN. It is what an account ATTACHES, and attaching
 * it is what an application needs, because the game server gates on
 * `accounts.discord_id` and that is the only identity it knows.
 *
 * So the callback does not write a session. It writes `portal_user_discord` for
 * the account that is already signed in, which requires a portal session to exist
 * — you cannot attach a Discord account without proving you are both the account
 * holder and the Discord account holder. That is why `authorizeUrl` is only ever
 * reachable from an authenticated page.
 *
 * Scope is `identify` and nothing else. `email`, `guilds` and `openid` would each
 * add a personal identifier this site has no use for.
 */
import 'server-only';

import { config, discordConfigured } from './config';

const DISCORD_AUTHORIZE = 'https://discord.com/oauth2/authorize';
const DISCORD_TOKEN = 'https://discord.com/api/oauth2/token';
const DISCORD_ME = 'https://discord.com/api/users/@me';

const DISCORD_IDENTITY = 'identify';

export interface DiscordIdentity {
  id: string;
  username: string;
  avatar: string | null;
}

/**
 * Where to send the browser to start the ATTACH round trip.
 *
 * `next` is the same-site return path the callback honours after a successful
 * link. It is echoed back through `state`, which is what stops a stranger from
 * feeding a forged `state` to the callback: the cookie was written by the server
 * and only this site's own start route can produce one.
 */
export function authorizeUrl(state: string): string {
  if (!discordConfigured) {
    throw new Error('Discord OAuth is not configured.');
  }

  const params = new URLSearchParams({
    client_id: config.discord.clientId,
    redirect_uri: config.discord.redirectUri,
    response_type: 'code',
    scope: DISCORD_IDENTITY,
    state,
    prompt: 'consent',
  });

  return `${DISCORD_AUTHORIZE}?${params.toString()}`;
}

/**
 * Exchange an authorization code for the identity behind it.
 *
 * Returns null for anything that is not a usable identity - a rejected exchange,
 * a malformed payload, or an ID that is not a Discord snowflake. An attach that
 * half-succeeded must not leave a link behind.
 */
export async function exchangeCode(
  code: string,
): Promise<DiscordIdentity | null> {
  if (!discordConfigured) return null;

  try {
    const response = await fetch(DISCORD_TOKEN, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: config.discord.clientId,
        client_secret: config.discord.clientSecret,
        grant_type: 'authorization_code',
        code,
        redirect_uri: config.discord.redirectUri,
      }),
      cache: 'no-store',
    });

    if (!response.ok) return null;

    const token = (await response.json()) as { access_token?: string };
    if (!token.access_token) return null;

    const meResponse = await fetch(DISCORD_ME, {
      headers: { Authorization: `Bearer ${token.access_token}` },
      cache: 'no-store',
    });

    if (!meResponse.ok) return null;

    const me = (await meResponse.json()) as {
      id?: string;
      username?: string;
      avatar?: string | null;
    };

    if (!me.id || !/^\d{5,32}$/.test(me.id)) return null;

    return {
      id: me.id,
      username: me.username ?? 'unknown',
      avatar: me.avatar ?? null,
    };
  } catch {
    // A network failure or a malformed JSON body are both "the attach did not
    // happen". They must not throw their way into a 500 that looks like a bug.
    return null;
  }
}

/**
 * The avatar URL to render for a Discord user, given their snowflake ID.
 *
 * Discord serves two flavours of avatar from its CDN:
 *
 *   - a custom one at `/avatars/{id}/{hash}.{ext}`, when the user has set one,
 *   - a built-in one at `/embed/avatars/{index}.png` for everyone else.
 *
 * The site does not store the custom-hash field (it is not in the schema), so
 * this function returns the built-in URL. The index is derived from the user
 * ID itself, which is the same formula Discord uses client-side, so the same
 * person always gets the same default picture and we never reach into a CDN
 * path that 404s.
 */
export function discordAvatarUrl(discordId: string): string {
  const index = Number((BigInt(discordId) >> 22n) % 6n);
  return `https://cdn.discordapp.com/embed/avatars/${index}.png`;
}