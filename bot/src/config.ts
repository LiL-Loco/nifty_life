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
  /**
   * The role Discord created for the bot itself.
   *
   * Recorded for one reason that is not tidiness: a bot's own role sits at the
   * TOP of the hierarchy, so it can hand itself any role below. If the bot role
   * were ever also configured as a staff role, the bot would mirror ITSELF into
   * the `staff` table — and a bot that can appoint itself moderator is worse than
   * no admin area at all. Refusing to start is the correct response.
   */
  botRoleId: string | null;
  db: {
    host: string;
    port: number;
    user: string;
    password: string;
    database: string;
  };
  /** Safety-net resync interval. Events handle the common case. */
  resyncMs: number;
  /**
   * Where the team area lives.
   *
   * Not cosmetic. The team link is deliberately NOT in the site's navigation —
   * it is reached from a pinned Discord message. That makes the bot the natural
   * place to know the address, and it prints it on every startup so the operator
   * never has to go looking for it.
   */
  adminUrl: string;
  /**
   * Channel where staff-side audit events are posted: bans, warns, joins,
   * leaves, whitelist changes. Empty means "no log channel, skip these".
   */
  staffLogChannelId: string | null;
  /**
   * Channel where the bot posts welcome / goodbye / auto-mod notifications
   * for the general audience. Empty means "skip these".
   */
  publicLogChannelId: string | null;
  /**
   * Channels where AutoMod watches for spam / link / caps violations. If
   * empty, AutoMod is active in every text channel the bot can see.
   */
  automodChannelIds: string[];
  /**
   * Discord channel-id for new-member welcome DMs. The DM itself is sent to
   * the joining user — this entry is the channel where the bot also drops a
   * public "say hi to <name>" embed so other members see new joins.
   */
  welcomeChannelId: string | null;
  /** URL the welcome DM/embed points new members at for the application. */
  applyUrl: string;
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

  const rawBotRole = (process.env.DISCORD_BOT_ROLE_ID ?? '').trim();
  const botRoleId = rawBotRole ? rawBotRole : null;

  if (botRoleId && !/^\d{5,32}$/.test(botRoleId)) {
    throw new Error(`DISCORD_BOT_ROLE_ID is not a valid Discord id: ${botRoleId}`);
  }

  if (botRoleId && staffRoleIds.includes(botRoleId)) {
    throw new Error(
      `DISCORD_BOT_ROLE_ID (${botRoleId}) is also listed in DISCORD_STAFF_ROLE_IDS. ` +
        'Refusing to start: the bot would mirror ITSELF into the staff table, and a bot ' +
        'that can appoint itself moderator is worse than no admin area.',
    );
  }

  const rawAdminUrl = (process.env.WEB_ADMIN_URL ?? '').trim();
  if (rawAdminUrl && !/^http?:\/\/[^\s]+$/.test(rawAdminUrl)) {
    throw new Error(`WEB_ADMIN_URL is not a valid http(s) URL: ${rawAdminUrl}`);
  }

  function optionalId(name: string): string | null {
    const raw = (process.env[name] ?? '').trim();
    if (!raw) return null;
    if (!/^\d{5,32}$/.test(raw)) {
      throw new Error(`${name} is not a valid Discord id: ${raw}`);
    }
    return raw;
  }

  const staffLogChannelId = optionalId('DISCORD_STAFF_LOG_CHANNEL_ID');
  const publicLogChannelId = optionalId('DISCORD_PUBLIC_LOG_CHANNEL_ID');
  const welcomeChannelId = optionalId('DISCORD_WELCOME_CHANNEL_ID');
  const automodChannelIds = (process.env.DISCORD_AUTOMOD_CHANNEL_IDS ?? '')
    .split(',')
    .map((id) => id.trim())
    .filter((id) => /^\d{5,32}$/.test(id));

  const applyUrlRaw = (process.env.WEB_APPLY_URL ?? '').trim();
  if (applyUrlRaw && !/^http?:\/\/[^\s]+$/.test(applyUrlRaw)) {
    throw new Error(`WEB_APPLY_URL is not a valid http(s) URL: ${applyUrlRaw}`);
  }
  const applyUrl = applyUrlRaw || 'https://colortastic.de/apply';

  return {
    token: required('DISCORD_BOT_TOKEN'),
    guildId: required('DISCORD_GUILD_ID'),
    staffRoleIds,
    botRoleId,
    adminUrl: rawAdminUrl,
    db: {
      host: process.env.DB_HOST ?? '127.0.0.1',
      port: Number(process.env.DB_PORT ?? 3306),
      user: required('DB_USER'),
      password: required('DB_PASSWORD'),
      database: process.env.DB_NAME ?? 'nifty_life',
    },
    resyncMs,
    staffLogChannelId,
    publicLogChannelId,
    welcomeChannelId,
    automodChannelIds,
    applyUrl,
  };
}