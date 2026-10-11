/**
 * Discord OAuth (ADR-0007).
 *
 * The whitelist identity is the Discord ID, and it is only trustworthy because it
 * comes back from Discord rather than from a form. Every write on this site
 * reads it out of the signed session instead of accepting one as input.
 *
 * A development login exists so the site can be built before an application
 * exists, but `config.ts` refuses to boot with it enabled in production.
 */
import 'server-only';

import { config, discordConfigured, loginMode } from './config';

const DISCORD_AUTHORIZE = 'https://discord.com/oauth2/authorize';
const DISCORD_TOKEN = 'https://discord.com/api/oauth2/token';
const DISCORD_ME = 'https://discord.com/api/users/@me';

const DISCORD_IDENTITY = 'identify';

export interface DiscordIdentity {
  id: string;
  username: string;
  avatar: string | null;
}

/** Where to send the browser to start the login round trip. */
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
 * a malformed payload, or an ID that is not a Discord snowflake. A login that
 * half-succeeded must not produce a session.
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
    // A network failure or a malformed JSON body are both "login did not
    // happen". They must not throw their way into a 500 that looks like a bug.
    return null;
  }
}

/**
 * The development identity, used when Discord is not configured.
 *
 * Returns null in production and whenever the ID is not set, so a half-filled
 * .env cannot quietly open the site.
 */
export function devIdentity(): DiscordIdentity | null {
  if (config.isProduction || loginMode() !== 'dev') return null;

  const id = config.discord.devDiscordId;
  if (!/^\d{5,32}$/.test(id)) return null;

  return { id, username: `dev#${id.slice(-4)}`, avatar: null };
}