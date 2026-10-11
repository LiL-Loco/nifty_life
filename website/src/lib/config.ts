/**
 * Environment configuration.
 *
 * The one rule that is load-bearing here: the database user must be the
 * restricted one. `nifty_website` has no UPDATE grant on `applications` and no
 * grant at all on `portal_users.email_verified_at`, which is what makes "the
 * website can never approve anybody and can never confirm its own address" a
 * property of the database rather than of code someone can get wrong. Pointing
 * this at `nifty` or `root` removes that boundary silently - no test fails, no
 * log line appears.
 *
 * There used to be a second rule here, refusing `DEV_AUTH` in production. That
 * development login let anybody claim any Discord ID, and it existed because
 * Discord WAS the login. It is gone with the login itself (migration 015): the
 * account is now made here with a password, so there is nothing left for a
 * switch to bypass.
 */

function required(name: string, value: string | undefined): string {
  if (!value || value.trim() === '') {
    throw new Error(
      `Missing environment variable ${name}. Copy website/.env.example to website/.env and fill it in.`,
    );
  }
  return value;
}

const isProduction = process.env.NODE_ENV === 'production';

// `next build` runs with NODE_ENV=production on the machine that will later run
// the app in development. Any check has to fire when the app SERVES, not when it
// is compiled - otherwise a build on this machine could not happen at all.
const isBuildPhase = process.env.NEXT_PHASE === 'phase-production-build';

/**
 * The redirect URI is the address Discord sends the player BACK to, and it must
 * match - exactly, character for character - one of the URLs registered under
 * OAuth2 → Redirects in the Developer Portal.
 *
 * The most common mistake by a wide margin is pasting the portal's *bot invite
 * link* here, because that is the other URL the portal shows you and it also
 * starts with `https://discord.com/oauth2/authorize`. Discord then answers
 * "invalid redirect_uri", which names neither the app, nor the URL, nor the
 * setting at fault.
 *
 * So we check the shape of it here rather than letting a confusing error travel
 * halfway to another company and back.
 */
function validateRedirectUri(uri: string): string {
  let parsed: URL;
  try {
    parsed = new URL(uri);
  } catch {
    throw new Error(
      `DISCORD_REDIRECT_URI is not a URL: "${uri}". It must be the address ` +
        'Discord returns to, e.g. http://localhost:3000/auth/callback',
    );
  }

  if (parsed.hostname === 'discord.com' || parsed.hostname.endsWith('.discord.com')) {
    throw new Error(
      'DISCORD_REDIRECT_URI points at discord.com. That is the bot invite link ' +
        'from the Developer Portal, not a redirect. Use your own address, e.g. ' +
        'http://localhost:3000/auth/callback, and add it under OAuth2 → Redirects.',
    );
  }

  if (parsed.search || parsed.hash) {
    throw new Error(
      'DISCORD_REDIRECT_URI must not contain a query string or fragment. ' +
        'Discord compares it literally against the registered value.',
    );
  }

  return uri;
}

export const config = {
  isProduction,

  db: {
    host: required('DB_HOST', process.env.DB_HOST),
    port: Number(process.env.DB_PORT ?? '3306'),
    user: required('DB_USER', process.env.DB_USER),
    password: required('DB_PASSWORD', process.env.DB_PASSWORD),
    database: required('DB_NAME', process.env.DB_NAME),
  },

  sessionSecret: required('SESSION_SECRET', process.env.SESSION_SECRET),

  /**
   * The public Discord invite, for the landing page.
   *
   * Optional on purpose: until it is set there is nothing to send a visitor to,
   * and the button says so rather than linking to nothing. A dead "JOIN DISCORD"
   * in the middle of the screen is the first thing anybody notices.
   */
  discordInvite: process.env.DISCORD_INVITE_URL ?? '',

  /**
   * This site's own base URL, absolute and without a trailing slash.
   *
   * It exists because a confirmation link is read in an EMAIL CLIENT, not in a
   * page: there is no request to derive a host from, and `x-forwarded-host` is
   * attacker-controlled anyway. Anything that builds a link the user will click
   * later builds it from here.
   */
  publicUrl: (process.env.PUBLIC_URL ?? 'http://localhost:3000').replace(/\/+$/, ''),

  discord: {
    clientId: process.env.DISCORD_CLIENT_ID ?? '',
    clientSecret: process.env.DISCORD_CLIENT_SECRET ?? '',
    redirectUri:
      process.env.DISCORD_REDIRECT_URI ?? 'http://localhost:3000/auth/callback',
  },
};

/**
 * True when a Discord round trip is possible at all.
 *
 * Used for exactly two decisions now: whether /account can offer the "connect
 * Discord" button, and whether the landing page's portal door leads somewhere
 * useful. It is NOT an authentication mode — there is no longer a Discord login
 * to fall back from.
 */
export const discordConfigured = Boolean(
  config.discord.clientId && config.discord.clientSecret,
);

// Only validated when Discord is actually in play - a deployment that has not
// created an application yet should still start and say so on the account page
// rather than crash on a placeholder value.
if (discordConfigured && !isBuildPhase) {
  validateRedirectUri(config.discord.redirectUri);
}