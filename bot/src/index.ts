/**
 * Nifty Life staff bot.
 *
 * One job: keep the `staff` table equal to "who currently holds a staff role in
 * our Discord server". It does not approve anything, does not talk to players,
 * and deliberately has no permissions of its own beyond reading members — an
 * approval button in Discord was replaced by the web admin area on purpose
 * (ADR-0007, revised 2026-10-11).
 *
 * Run: npm install && npm run build && npm start
 */
import { Client, GatewayIntentBits, Partials, type GuildMember, type Guild } from 'discord.js';

import { loadConfig } from './config.js';
import { StaffMirror } from './mirror.js';

async function main(): Promise<void> {
  const config = loadConfig();
  const mirror = new StaffMirror(config);

  const client = new Client({
    // GuildMembers is required to know WHO holds a role. It is a privileged
    // intent, which is why the bot must be in the server with that intent
    // enabled in the Developer Portal — not a code concern.
    intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMembers],
    partials: [Partials.GuildMember],
  });

  /** The staff role this member holds, or null. First match wins if several. */
  function staffRoleOf(member: GuildMember | null): string | null {
    if (!member) return null;
    const held = member.roles.cache;
    for (const roleId of config.staffRoleIds) {
      if (held.has(roleId)) return roleId;
    }
    return null;
  }

  /** Read every member currently holding a staff role. */
  async function collectStaff(guild: Guild) {
    await guild.members.fetch();

    const entries: { discordId: string; roleId: string }[] = [];
    for (const member of guild.members.cache.values()) {
      const roleId = staffRoleOf(member);
      if (roleId) entries.push({ discordId: member.id, roleId });
    }
    return entries;
  }

  async function fullSync(guild: Guild): Promise<void> {
    const entries = await collectStaff(guild);
    const { added, removed } = await mirror.fullSync(entries);
    console.log(`[sync] guild=${guild.name} staff=${added} removed=${removed}`);
  }

  client.once('ready', async () => {
    const guild = client.guilds.cache.get(config.guildId);
    if (!guild) {
      // Fail loudly rather than sit connected and syncing nothing. A bot that is
      // not in the guild is the single most likely reason the mirror is empty.
      console.error(
        `[fatal] Bot is not in guild ${config.guildId}. Invite it first, then start again.`,
      );
      process.exit(1);
    }

    console.log(`[ready] connected as ${client.user?.tag ?? 'unknown'}`);

    try {
      await fullSync(guild);
      console.log(`[ready] staff mirror holds ${await mirror.count()} row(s)`);
    } catch (error) {
      console.error('[fatal] initial sync failed:', error);
      process.exit(1);
    }
  });

  // Incremental updates. A role change is one event and one row, so /admin
  // reflects a promotion or a removal immediately.
  client.on('guildMemberAdd', async (member) => {
    if (member.guild.id !== config.guildId) return;
    const roleId = staffRoleOf(member);
    if (roleId) await mirror.upsert(member.id, roleId);
  });

  client.on('guildMemberUpdate', async (_old, member) => {
    if (member.guild.id !== config.guildId) return;
    const roleId = staffRoleOf(member);
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

  // Safety net. Events are missed when the bot is briefly offline, and a missed
  // removal is a moderator who keeps access to /admin until someone notices.
  setInterval(() => {
    const guild = client.guilds.cache.get(config.guildId);
    if (!guild) return;
    fullSync(guild).catch((error) => console.error('[sync] periodic sync failed:', error));
  }, config.resyncMs);

  client.on('error', (error) => console.error('[discord]', error));
  client.on('shardError', (error) => console.error('[discord shard]', error));

  await client.login(config.token);

  const shutdown = async (signal: string) => {
    console.log(`[shutdown] ${signal}`);
    await client.destroy();
    await mirror.close();
    process.exit(0);
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
}

main().catch((error) => {
  console.error('[fatal]', error);
  process.exit(1);
});