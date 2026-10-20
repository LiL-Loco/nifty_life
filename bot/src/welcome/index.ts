/**
 * Welcome / goodbye: DM new members, post a public hello in the welcome
 * channel, and announce leaves.
 *
 * The DM carries the actual useful information (whitelist status + apply link).
 * The public embed is a single line so the channel doesn't become a wall of
 * noise on join-storms.
 *
 * Whitelist status is derived from `accounts.status='active'` — the same
 * source-of-truth the FiveM connect check uses. We don't trust the bot's
 * own idea of "who's staff" here, because the question is "may they
 * connect", not "may they moderate".
 */
import { EmbedBuilder, GuildMember, TextChannel } from 'discord.js';
import type { Client } from 'discord.js';
import type { Pool } from 'mysql2/promise';

export interface WelcomeContext {
  client: Client;
  pool: Pool;
  guildId: string;
  welcomeChannelId: string | null;
  publicLogChannelId: string | null;
  staffLogChannelId: string | null;
  applyUrl: string;
}

export function attachWelcome(client: Client, ctx: WelcomeContext): void {
  client.on('guildMemberAdd', async (member) => {
    if (member.guild.id !== ctx.guildId) return;
    await onJoin(ctx, member as unknown as GuildMember);
  });

  client.on('guildMemberRemove', async (member) => {
    if (member.guild.id !== ctx.guildId) return;
    await onLeave(ctx, member as unknown as GuildMember);
  });
}

async function onJoin(ctx: WelcomeContext, member: GuildMember): Promise<void> {
  const status = await lookupWhitelist(ctx, member.id);
  const dmText = status === 'active'
    ? `Willkommen auf Nifty Life! Du bist bereits für den FiveM-Server freigeschaltet.`
    : `Willkommen auf Nifty Life! Bewirb dich, um den FiveM-Server zu spielen: ${ctx.applyUrl}`;
  member
    .send({
      embeds: [
        new EmbedBuilder()
          .setColor(0x6b4f9e)
          .setTitle(`Willkommen auf Nifty Life, ${member.user.username}`)
          .setDescription(dmText)
          .setFooter({ text: `Whitelist-Status: ${status ?? 'nicht beantragt'}` }),
      ],
    })
    .catch(() => undefined);

  // Public hello. Short on purpose — join-storms become walls otherwise.
  if (ctx.welcomeChannelId) {
    const ch = await ctx.client.channels.fetch(ctx.welcomeChannelId).catch(() => null);
    if (ch && ch.isSendable()) {
      await ch.send({
        embeds: [
          new EmbedBuilder()
            .setColor(0x6bbf6b)
            .setDescription(
              `<@${member.id}> ist beigetreten. ${status === 'active' ? '🎮 Schon gewhitelisted.' : '📝 Noch nicht beantragt.'}`,
            ),
        ],
      });
    }
  }
}

async function onLeave(ctx: WelcomeContext, member: GuildMember): Promise<void> {
  if (!ctx.publicLogChannelId) return;
  const ch = await ctx.client.channels.fetch(ctx.publicLogChannelId).catch(() => null);
  if (!ch || !ch.isSendable()) return;
  await ch.send({
    embeds: [
      new EmbedBuilder()
        .setColor(0xc94f4f)
        .setDescription(`**${member.user.tag}** hat den Server verlassen.`)
        .setTimestamp(new Date()),
    ],
  });
}

async function lookupWhitelist(
  ctx: WelcomeContext,
  discordId: string,
): Promise<'active' | 'suspended' | 'pending' | null> {
  const rows = (await ctx.pool.execute(
    `SELECT status FROM accounts WHERE discord_id = ? LIMIT 1`,
    [discordId],
  )) as unknown as [{ status: string }];
  const row = (rows as any)[0];
  return (row?.status as 'active' | 'suspended' | 'pending' | null) ?? null;
}

/** Exposed for embed-builder reuse. */
export type _TextChannelRef = TextChannel;