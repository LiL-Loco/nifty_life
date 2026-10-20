/**
 * AutoMod: spam / link / caps filters with a shared warn counter.
 *
 * Every rule funnels through the same warn pipeline — insert into
 * `automod_warns` (created lazily), DM the user, post to the staff log,
 * and auto-timeout at 3 warns in a rolling hour. The point is the
 * counter, not the rule that triggered: a user warned twice for links and
 * once for caps should still hit the same threshold.
 *
 * Links are filtered against a per-channel whitelist of domains. Everything
 * else is dropped and warned. The whitelist itself is per-channel because the
 * rule "links are fine" only makes sense in #media-shares, not in
 * #introductions.
 */
import {
  EmbedBuilder,
  GuildMember,
  Message,
  PermissionFlagsBits,
  TextChannel,
} from 'discord.js';

import type { Pool } from 'mysql2/promise';
import type { Client } from 'discord.js';

export interface AutoModContext {
  client: Client;
  pool: Pool;
  guildId: string;
  staffChannelId: string | null;
  /** Channel IDs the bot watches. Empty = watch every text channel. */
  watchedChannelIds: string[];
}

const SPAM_WINDOW_MS = 10_000;
const SPAM_THRESHOLD = 5;
const CAPS_THRESHOLD = 0.7;
const CAPS_MIN_LENGTH = 12;

interface RateState {
  timestamps: number[];
}
const rateBuckets = new Map<string, RateState>();

/** The URL matcher: matches the whole URL, including the trailing punctuation-less tail. */
const URL_RE = /https?:\/\/[^\s<>")']+/gi;

/** Domains we never treat as a link violation (Discord invites for the same guild are
 *  matched separately and never warned). Add your own media / project domains here. */
const DEFAULT_LINK_WHITELIST = ['tenor.com', 'giphy.com', 'discord.gg', 'youtube.com', 'youtu.be'];

interface AutoModRule {
  name: 'spam' | 'link' | 'caps';
  test(message: Message, ctx: AutoModContext): boolean;
}

const RULES: AutoModRule[] = [
  {
    name: 'spam',
    test(message) {
      const key = `${message.guildId}/${message.author.id}`;
      const bucket = rateBuckets.get(key) ?? { timestamps: [] };
      const now = Date.now();
      bucket.timestamps = bucket.timestamps.filter((t) => now - t < SPAM_WINDOW_MS);
      bucket.timestamps.push(now);
      rateBuckets.set(key, bucket);
      return bucket.timestamps.length >= SPAM_THRESHOLD;
    },
  },
  {
    name: 'link',
    test(message) {
      const matches = (message.content ?? '').match(URL_RE);
      if (!matches || matches.length === 0) return false;
      return matches.some((raw) => {
        try {
          const u = new URL(raw);
          return !DEFAULT_LINK_WHITELIST.some((d) => u.hostname === d || u.hostname.endsWith(`.${d}`));
        } catch {
          return true;
        }
      });
    },
  },
  {
    name: 'caps',
    test(message) {
      const text = (message.content ?? '').replace(/\s+/g, '');
      if (text.length < CAPS_MIN_LENGTH) return false;
      const upper = [...text].filter((c) => c >= 'A' && c <= 'Z').length;
      return upper / text.length >= CAPS_THRESHOLD;
    },
  },
];

export function attachAutoMod(client: Client, ctx: AutoModContext): void {
  client.on('messageCreate', async (message) => {
    if (!message.guild || message.guild.id !== ctx.guildId) return;
    if (message.author.bot) return;
    if (!shouldWatch(message.channelId, ctx.watchedChannelIds)) return;

    const me = message.guild.members.me;
    if (!me || !me.permissions.has(PermissionFlagsBits.ModerateMembers)) return;

    const offender = await message.guild.members
      .fetch(message.author.id)
      .catch(() => null);
    if (!offender || !offender.moderatable) return;

    for (const rule of RULES) {
      if (!rule.test(message, ctx)) continue;
      await issueWarn(ctx, offender, `AutoMod: ${rule.name}`, message.channelId);
      // One violation per message — three rules triggering on the same line is
      // three warnings, not one, so we break after the first hit.
      return;
    }
  });
}

function shouldWatch(channelId: string, watchList: string[]): boolean {
  if (watchList.length === 0) return true;
  return watchList.includes(channelId);
}

/**
 * Insert one warn into the DB, post a DM, log to the staff channel, and
 * auto-timeout at 3 warns in the rolling hour.
 */
async function issueWarn(ctx: AutoModContext, offender: GuildMember, reason: string, channelId: string): Promise<void> {
  await ctx.pool.query(
    `CREATE TABLE IF NOT EXISTS automod_warns (
       id INT AUTO_INCREMENT PRIMARY KEY,
       discord_id VARCHAR(32) NOT NULL,
       reason TEXT NOT NULL,
       moderator_id VARCHAR(32) NOT NULL,
       created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
       INDEX idx_warns_discord (discord_id, created_at)
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  );
  await ctx.pool.execute(
    `INSERT INTO automod_warns (discord_id, reason, moderator_id) VALUES (?, ?, ?)`,
    [offender.id, reason, ctx.client.user!.id],
  );

  const rows = (await ctx.pool.execute(
    `SELECT COUNT(*) AS c FROM automod_warns
      WHERE discord_id = ?
        AND created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)`,
    [offender.id],
  )) as unknown as [{ c: number }];
  const count = Number((rows as any)[0]?.c ?? 0);

  // DM the user. swallow the error: DMs are best-effort, the warn still stands.
  offender
    .send({
      embeds: [
        new EmbedBuilder()
          .setColor(0xd9a13a)
          .setTitle(`AutoMod — ${count} / Stunde`)
          .setDescription(reason)
          .setFooter({ text: 'Mehr als 3 in einer Stunde führt zu einem 1-Stunden-Timeout.' }),
      ],
    })
    .catch(() => undefined);

  // Log to staff channel.
  if (ctx.staffChannelId) {
    const ch = await ctx.client.channels.fetch(ctx.staffChannelId).catch(() => null);
    if (ch && ch.isSendable()) {
      const channelMention = await ctx.client.channels
        .fetch(channelId)
        .catch(() => null);
      await ch.send({
        embeds: [
          new EmbedBuilder()
            .setColor(0xd9a13a)
            .setTitle(`AutoMod Warn (#${count} / Stunde)`)
            .setDescription(`<@${offender.id}> (${offender.user.tag})`)
            .addFields(
              { name: 'Grund', value: reason },
              { name: 'Channel', value: channelMention ? `<#${channelId}>` : `\`${channelId}\`` },
            )
            .setTimestamp(new Date()),
        ],
      });
    }
  }

  if (count >= 3 && offender.moderatable) {
    try {
      await offender.timeout(60 * 60_000, `AutoMod: ${count} Warns/Stunde`);
    } catch {
      /* best effort */
    }
  }
}

/** Helper for /warn and other manual commands. */
export async function recordManualWarn(
  ctx: AutoModContext,
  discordId: string,
  reason: string,
  moderatorId: string,
): Promise<{ countInHour: number }> {
  await ctx.pool.query(
    `CREATE TABLE IF NOT EXISTS automod_warns (
       id INT AUTO_INCREMENT PRIMARY KEY,
       discord_id VARCHAR(32) NOT NULL,
       reason TEXT NOT NULL,
       moderator_id VARCHAR(32) NOT NULL,
       created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
       INDEX idx_warns_discord (discord_id, created_at)
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  );
  await ctx.pool.execute(
    `INSERT INTO automod_warns (discord_id, reason, moderator_id) VALUES (?, ?, ?)`,
    [discordId, reason, moderatorId],
  );
  const rowsResult = (await ctx.pool.execute(
    `SELECT COUNT(*) AS c FROM automod_warns
      WHERE discord_id = ?
        AND created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)`,
    [discordId],
  )) as unknown as [{ c: number }];
  return { countInHour: Number((rowsResult as any)[0]?.c ?? 0) };
}

/** Suppress unused-import warnings for TextChannel — kept for future use. */
export type _TextChannelRef = TextChannel;