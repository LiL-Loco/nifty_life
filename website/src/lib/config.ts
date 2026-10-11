/**
 * Environment configuration.
 *
 * Two rules live here and both are load-bearing:
 *
 *  1. The database user must be the restricted one. `nifty_website` has no
 *     UPDATE grant anywhere, which is what makes "the website can never approve
 *     an application" a property of the database rather than of code someone can
 *     get wrong. Pointing this at `nifty` or `root` removes that boundary
 *     silently — no test fails, no log line appears.
 *
 *  2. Development auth must never survive into production. It lets anyone claim
 *     any Discord ID, so it is a complete authentication bypass. We refuse to
 *     boot rather than trust that nobody flipped a flag.
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
// the app in development. The guard therefore has to fire when the app SERVES,
// not when it is compiled — otherwise a developer-auth build cannot be built at
// all, and the fix would be to delete the guard.
const isBuildPhase = process.env.NEXT_PHASE === 'phase-production-build';

const devAuthWanted = process.env.DEV_AUTH === 'true';

if (!isBuildPhase && isProduction && devAuthWanted) {
  throw new Error(
    'DEV_AUTH=true is refused while NODE_ENV=production. It is a full ' +
      'authentication bypass and must never be reachable from the internet.',
  );
}

export const config = {
  isProduction,
  devAuth: devAuthWanted,

  db: {
    host: required('DB_HOST', process.env.DB_HOST),
    port: Number(process.env.DB_PORT ?? '3306'),
    user: required('DB_USER', process.env.DB_USER),
    password: required('DB_PASSWORD', process.env.DB_PASSWORD),
    database: required('DB_NAME', process.env.DB_NAME),
  },

  sessionSecret: required('SESSION_SECRET', process.env.SESSION_SECRET),

  discord: {
    clientId: process.env.DISCORD_CLIENT_ID ?? '',
    clientSecret: process.env.DISCORD_CLIENT_SECRET ?? '',
    redirectUri:
      process.env.DISCORD_REDIRECT_URI ?? 'http://localhost:3000/auth/callback',
    // Development login is only offered when Discord is not configured at all.
    devDiscordId: process.env.DEV_DISCORD_ID ?? '',
  },
};

/** True when a real Discord OAuth round trip is possible. */
export const discordConfigured = Boolean(
  config.discord.clientId && config.discord.clientSecret,
);

/** Which login paths this instance will actually offer. */
export function loginMode(): 'discord' | 'dev' | 'unavailable' {
  if (discordConfigured) return 'discord';
  if (config.devAuth) return 'dev';
  return 'unavailable';
}