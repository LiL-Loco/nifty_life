/**
 * Bot configuration.
 *
 * Read from the environment, never hardcoded, and never from a checked-in file.
 * The token in particular is the only thing in this project that can change who
 * is staff, so it is read exactly here and passed around as a value.
 */

export interface BotConfig {
  token: string;
  guildId: string;
  /** Several roles may count as staff. Empty means the bot refuses to start. */
  staffRoleIds: string[];
  db: {
    host: string;
    port: number;
    user: string;
    password: string;
    database: string;
  };
  /** Safety-net resync interval. Events handle the common case. */
  resyncMs: number;
}

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing environment variable ${name}. See bot/.env.example.`);
  return value.trim();
}

export function loadConfig(): BotConfig {
  const staffRoleIds = (process.env.DISCORD_STAFF_ROLE_IDS ?? '')
    .split(',')
    .map((id) => id.trim())
    .filter((id) => /^\d{5,32}$/.test(id));

  // Refusing to start is the point. A bot with no staff role configured would
  // sync an EMPTY table and lock every moderator out of /admin while looking
  // perfectly healthy in the console.
  if (staffRoleIds.length === 0) {
    throw new Error(
      'DISCORD_STAFF_ROLE_IDS is empty. Refusing to start: an empty staff list would ' +
        'silently lock everyone out of /admin.',
    );
  }

  const resyncMs = Number(process.env.STAFF_RESYNC_MS ?? 900000);
  if (!Number.isFinite(resyncMs) || resyncMs < 60000) {
    throw new Error('STAFF_RESYNC_MS must be a number of at least 60000 (one minute).');
  }

  return {
    token: required('DISCORD_BOT_TOKEN'),
    guildId: required('DISCORD_GUILD_ID'),
    staffRoleIds,
    db: {
      host: process.env.DB_HOST ?? '127.0.0.1',
      port: Number(process.env.DB_PORT ?? 3306),
      user: required('DB_USER'),
      password: required('DB_PASSWORD'),
      database: process.env.DB_NAME ?? 'nifty_life',
    },
    resyncMs,
  };
}