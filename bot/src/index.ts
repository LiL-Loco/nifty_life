/**
 * Nifty Life bot — staff mirror + slash commands + automod + welcome + tickets.
 *
 * Run: npm install && npm run build && npm start
 *
 * On startup the bot:
 *   1. Connects to MySQL with the GAME account (only `nifty` may write `staff`,
 *      `accounts`, `automod_warns`).
 *   2. Registers slash commands against the configured guild.
 *   3. Performs the initial staff sync; on failure the bot refuses to start —
 *      a bot that connected but synced zero rows has either wrong credentials
 *      or the Server Members Intent off, and silently sitting connected is the
 *      worst possible next state.
 *   4. Hooks up: staff mirror events, automod, welcome, tickets, slash-command
 *      interaction router.
 */
import { Client, GatewayIntentBits, GuildMember, Partials, type Guild } from 'discord.js';
import mysql from 'mysql2/promise';

import { loadConfig } from './config.js';
import { StaffMirror } from './mirror.js';
import { attachAutoMod, type AutoModContext } from './moderation/index.js';
import { attachWelcome, type WelcomeContext } from './welcome/index.js';
import { attachTickets, ticketCommand } from './tickets/index.js';
import {
  registerCommands,
  attachInteractionHandler,
  type BotContext,
} from './commands/index.js';

interface BotExtras {
  pool: mysql.Pool;
  guildId: string;
  staffChannelId?: string;
  publicLogChannelId?: string;
  welcomeChannelId?: string;
  webAdminUrl?: string;
  watchedChannels: string[];
  staffRoleIds: string[];
}

async function main(): Promise<void> {
  const config = loadConfig();

  const pool = mysql.createPool({
    host: config.db.host,
    port: config.db.port,
    user: config.db.user,
    password: config.db.password,
    database: config.db.database,
    connectionLimit: 4,
    waitForConnections: true,
    multipleStatements: false,
  });

  const mirror = new StaffMirror(config);

  const client = new Client({
    intents: [
      GatewayIntentBits.Guilds,
      GatewayIntentBits.GuildMembers,
      // MessageContent + GuildMessages are PRIVILEGED intents — must be enabled
      // in the Discord Developer Portal under Bot → Privileged Gateway Intents.
      // Without them, AutoMod cannot inspect message contents (spam/link/caps)
      // and welcome DMs cannot be sent. The bot starts either way, but those
      // features become no-ops until the portal toggle is flipped.
      GatewayIntentBits.GuildMessages,
      GatewayIntentBits.MessageContent,
      GatewayIntentBits.DirectMessages,
    ],
    partials: [Partials.GuildMember, Partials.Channel, Partials.Message],
  });

  // Stash on the client for the interaction router; avoids re-passing context
  // through every callback. Cast through unknown because we don't want to
  // widen the discord.js types.
  (client as unknown as { __nifty_pool: typeof pool }).__nifty_pool = pool;
  (client as unknown as { __nifty_guildId: string }).__nifty_guildId = config.guildId;
  (client as unknown as { __nifty_staffChannelId?: string }).__nifty_staffChannelId =
    config.staffLogChannelId ?? undefined;
  (client as unknown as { __nifty_webAdminUrl?: string }).__nifty_webAdminUrl =
    config.adminUrl || undefined;

  // Wire up the modules BEFORE logging in — events fire from the moment the
  // socket opens, and missing a `guildMemberAdd` because the handler wasn't
  // attached yet is a real failure mode on reconnects.
  attachAutoMod(client, {
    client,
    pool,
    guildId: config.guildId,
    staffChannelId: config.staffLogChannelId,
    watchedChannelIds: config.automodChannelIds,
  } satisfies AutoModContext);

  attachWelcome(client, {
    client,
    pool,
    guildId: config.guildId,
    welcomeChannelId: config.welcomeChannelId,
    publicLogChannelId: config.publicLogChannelId,
    staffLogChannelId: config.staffLogChannelId,
    applyUrl: config.applyUrl,
  } satisfies WelcomeContext);

  if (config.staffLogChannelId && config.welcomeChannelId) {
    attachTickets(client, {
      client,
      pool,
      guildId: config.guildId,
      panelChannelId: config.welcomeChannelId,
      ticketParentChannelId: config.welcomeChannelId,
      staffRoleIds: config.staffRoleIds,
      transcriptChannelId: config.staffLogChannelId,
    });
  }

  attachInteractionHandler(client);

  client.once('clientReady', async () => {
    const guild = client.guilds.cache.get(config.guildId);
    if (!guild) {
      console.error(`[fatal] Bot is not in guild ${config.guildId}. Invite it first, then start again.`);
      process.exit(1);
    }

    console.log(`[ready] connected as ${client.user?.tag ?? 'unknown'}`);
    console.log(`[ready] guild=${guild.name} bot-role=${config.botRoleId ?? 'unknown'}`);

    try {
      await fullSync(guild, config, mirror);
      console.log(`[ready] staff mirror holds ${await mirror.count()} row(s)`);

      await registerCommands(client, config.guildId);

      if (config.adminUrl) {
        console.log(`[ready] team area: ${config.adminUrl}`);
      } else {
        console.log('[ready] WEB_ADMIN_URL is not set.');
      }
    } catch (error) {
      console.error('[fatal] startup failed:', error);
      process.exit(1);
    }
  });

  // Incremental staff updates.
  client.on('guildMemberAdd', async (member) => {
    if (member.guild.id !== config.guildId) return;
    const roleId = staffRoleOf(member, config.staffRoleIds);
    if (roleId) await mirror.upsert(member.id, roleId);
  });

  client.on('guildMemberUpdate', async (_old, member) => {
    if (member.guild.id !== config.guildId) return;
    const roleId = staffRoleOf(member, config.staffRoleIds);
    if (roleId) {
      await mirror.upsert(member.id, roleId);
    } else {
      await mirror.remove(member.id);
    }
  });

  client.on('guildMemberRemove', async (member) => {
    if (member.guild.id !== config.guildId) return;
    await mirror.remove(member.id);
  });

  // Safety-net periodic sync. Events are missed when the bot is briefly offline.
  setInterval(() => {
    const guild = client.guilds.cache.get(config.guildId);
    if (!guild) return;
    fullSync(guild, config, mirror).catch((error) =>
      console.error('[sync] periodic sync failed:', error),
    );
  }, config.resyncMs);

  client.on('error', (error) => console.error('[discord]', error));
  client.on('shardError', (error) => console.error('[discord shard]', error));

  await client.login(config.token);

  const shutdown = async (signal: string) => {
    console.log(`[shutdown] ${signal}`);
    await client.destroy();
    await mirror.close();
    await pool.end();
    process.exit(0);
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));

  // Silence the unused warning for ticketCommand — it's only there so the
  // command shows up in the registry; the real wiring is in attachTickets.
  void ticketCommand;
}

function staffRoleOf(member: GuildMember | null, staffRoleIds: string[]): string | null {
  if (!member) return null;
  const held = member.roles.cache;
  for (const roleId of staffRoleIds) {
    if (held.has(roleId)) return roleId;
  }
  return null;
}

async function fullSync(guild: Guild, config: ReturnType<typeof loadConfig>, mirror: StaffMirror): Promise<void> {
  const before = guild.members.cache.size;
  await guild.members.fetch();
  const after = guild.members.cache.size;
  console.log(`[sync] members ${before} -> ${after}, staff roles ${config.staffRoleIds.join(',')}`);

  const entries: { discordId: string; roleId: string }[] = [];
  for (const member of guild.members.cache.values()) {
    const roleId = staffRoleOf(member, config.staffRoleIds);
    console.log(`[sync]   ${member.user.username}: roles=[${[...member.roles.cache.keys()].join(',')}] staff=${roleId ?? '-'}`);
    if (roleId) entries.push({ discordId: member.id, roleId });
  }
  const { added, removed } = await mirror.fullSync(entries);
  console.log(`[sync] guild=${guild.name} staff=${added} removed=${removed}`);
}

main().catch((error) => {
  console.error('[fatal]', error);
  process.exit(1);
});