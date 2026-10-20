/**
 * Moderation slash commands: /ban, /unban, /warn, /timeout, /clear.
 *
 * Every action that touches Discord state is mirrored into the staff log
 * channel so the team has a single audit trail.
 *
 * Warn counts live in `automod_warns` (created lazily by the moderation
 * module). The auto-timeout threshold is reached at 3 warns in a rolling
 * hour.
 */
import {
  ChatInputCommandInteraction,
  EmbedBuilder,
  GuildMember,
  PermissionFlagsBits,
  SlashCommandBuilder,
  TextChannel,
} from 'discord.js';

import type { BotContext, Command } from './account.js';
import { isCallerStaff } from './account.js';
import { logToStaffChannel } from './whitelist.js';

interface CommandContext {
  client: BotContext['client'];
  pool: BotContext['pool'];
  guildId: string;
  staffChannelId?: string;
}

export const commands: Command[] = [
  {
    data: new SlashCommandBuilder()
      .setName('ban')
      .setDescription('Ban a member. Requires MANAGE_BANS.')
      .addUserOption((o) => o.setName('user').setDescription('Who to ban.').setRequired(true))
      .addStringOption((o) => o.setName('reason').setDescription('Why.').setRequired(true).setMaxLength(500))
      .addIntegerOption((o) =>
        o
          .setName('delete_days')
          .setDescription('Delete their last 0–7 days of messages.')
          .setMinValue(0)
          .setMaxValue(7),
      ),
    staffOnly: true,
    execute: async (interaction, ctx) => await execBan(interaction, ctx),
  },
  {
    data: new SlashCommandBuilder()
      .setName('unban')
      .setDescription('Unban by id. Requires MANAGE_BANS.')
      .addStringOption((o) =>
        o.setName('user_id').setDescription('Discord user id (snowflake).').setRequired(true),
      )
      .addStringOption((o) =>
        o.setName('reason').setDescription('Why.').setRequired(false).setMaxLength(500),
      ),
    staffOnly: true,
    execute: async (interaction, ctx) => await execUnban(interaction, ctx),
  },
  {
    data: new SlashCommandBuilder()
      .setName('warn')
      .setDescription('Issue a warning. Persisted in the DB; counts toward auto-timeout.')
      .addUserOption((o) => o.setName('user').setDescription('Who to warn.').setRequired(true))
      .addStringOption((o) =>
        o.setName('reason').setDescription('Why.').setRequired(true).setMaxLength(500),
      ),
    staffOnly: true,
    execute: async (interaction, ctx) => await execWarn(interaction, ctx),
  },
  {
    data: new SlashCommandBuilder()
      .setName('timeout')
      .setDescription('Timeout a member for N minutes (max 40320 / 28 days). Requires MODERATE_MEMBERS.')
      .addUserOption((o) => o.setName('user').setDescription('Who to timeout.').setRequired(true))
      .addIntegerOption((o) =>
        o.setName('minutes').setDescription('Duration in minutes.').setRequired(true).setMinValue(1).setMaxValue(40320),
      )
      .addStringOption((o) =>
        o.setName('reason').setDescription('Why.').setRequired(true).setMaxLength(500),
      ),
    staffOnly: true,
    execute: async (interaction, ctx) => await exec(interaction, ctx),
  },
  {
    data: new SlashCommandBuilder()
      .setName('clear')
      .setDescription('Bulk-delete the last N messages in this channel (1–100). Requires MANAGE_MESSAGES.')
      .addIntegerOption((o) =>
        o.setName('count').setDescription('How many.').setRequired(true).setMinValue(1).setMaxValue(100),
      )
      .addUserOption((o) => o.setName('from_user').setDescription('Only delete messages by this user.').setRequired(false)),
    staffOnly: true,
    execute: async (interaction, ctx) => await execClear(interaction, ctx),
  },
];

async function execBan(interaction: ChatInputCommandInteraction, ctx: BotContext): Promise<void> {
  if (!(await isCallerStaff(interaction, ctx))) {
    await interaction.reply({ content: 'Nur für Staff.', ephemeral: true });
    return;
  }
  const me = interaction.guild?.members.me;
  if (!me || !me.permissions.has(PermissionFlagsBits.BanMembers)) {
    await interaction.reply({ content: 'Bot fehlt BanMembers.', ephemeral: true });
    return;
  }
  const user = interaction.options.getUser('user', true);
  const reason = interaction.options.getString('reason', true);
  const deleteDays = interaction.options.getInteger('delete_days') ?? 0;
  try {
    await interaction.guild!.members.ban(user, {
      reason,
      deleteMessageSeconds: deleteDays * 86400,
    });
  } catch (e) {
    await interaction.reply({ content: `Fehler: ${(e as Error).message}`, ephemeral: true });
    return;
  }
  await logToStaffChannel(ctx, {
    title: 'Ban',
    description: `<@${user.id}> (${user.tag})`,
    fields: [{ name: 'Grund', value: reason }, { name: 'Historie', value: `${deleteDays}d` }],
    footer: `von ${interaction.user.tag}`,
    color: 0xc94f4f,
  });
  await interaction.reply({
    embeds: [new EmbedBuilder().setColor(0xc94f4f).setTitle('Banned').setDescription(`<@${user.id}> — ${reason}`)],
  });
}

async function execUnban(interaction: ChatInputCommandInteraction, ctx: BotContext): Promise<void> {
  if (!(await isCallerStaff(interaction, ctx))) {
    await interaction.reply({ content: 'Nur für Staff.', ephemeral: true });
    return;
  }
  const me = interaction.guild?.members.me;
  if (!me || !me.permissions.has(PermissionFlagsBits.BanMembers)) {
    await interaction.reply({ content: 'Bot fehlt BanMembers.', ephemeral: true });
    return;
  }
  const userId = interaction.options.getString('user_id', true);
  const reason = interaction.options.getString('reason') ?? 'kein Grund';
  try {
    await interaction.guild!.members.unban(userId, reason);
  } catch (e) {
    await interaction.reply({ content: `Fehler: ${(e as Error).message}`, ephemeral: true });
    return;
  }
  await logToStaffChannel(ctx, {
    title: 'Unban',
    description: `<@${userId}>`,
    fields: [{ name: 'Grund', value: reason }],
    footer: `von ${interaction.user.tag}`,
    color: 0x6bbf6b,
  });
  await interaction.reply({
    embeds: [new EmbedBuilder().setColor(0x6bbf6b).setTitle('Unbanned').setDescription(`<@${userId}>`)],
  });
}

async function execWarn(interaction: ChatInputCommandInteraction, ctx: BotContext): Promise<void> {
  if (!(await isCallerStaff(interaction, ctx))) {
    await interaction.reply({ content: 'Nur für Staff.', ephemeral: true });
    return;
  }
  const user = interaction.options.getUser('user', true);
  const reason = interaction.options.getString('reason', true);

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
    [user.id, reason, interaction.user.id],
  );

  const [rows] = await ctx.pool.execute(
    `SELECT COUNT(*) AS c FROM automod_warns
      WHERE discord_id = ?
        AND created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)`,
    [user.id],
  );
  const count = Number((rows as { c: number }[])[0]?.c ?? 0);

  await logToStaffChannel(ctx, {
    title: `Warn (#${count} / Stunde)`,
    description: `<@${user.id}> (${user.tag})`,
    fields: [{ name: 'Grund', value: reason }],
    footer: `von ${interaction.user.tag}`,
    color: 0xd9a13a,
  });

  await interaction.reply({
    embeds: [
      new EmbedBuilder()
        .setColor(0xd9a13a)
        .setTitle('Warned')
        .setDescription(`<@${user.id}> — ${reason}\n\nWarns in der letzten Stunde: **${count}**.`)
        .setFooter({ text: 'Schwelle für Auto-Mod-Aktion ist 3 / Stunde.' }),
    ],
  });

  if (count >= 3) {
    const member = (await interaction.guild!.members.fetch(user.id).catch(() => null)) as GuildMember | null;
    if (member && member.moderatable) {
      try {
        await member.timeout(60 * 60_000, `Auto-Mod: ${count} Warns/Stunde`);
        await logToStaffChannel(ctx, {
          title: 'Auto-Mod: Timeout (1h)',
          description: `<@${user.id}>`,
          fields: [{ name: 'Grund', value: `${count} Warns in der letzten Stunde` }],
          color: 0xc94f4f,
        });
      } catch {
        /* best effort */
      }
    }
  }
}

async function exec(interaction: ChatInputCommandInteraction, ctx: BotContext): Promise<void> {
  if (!(await isCallerStaff(interaction, ctx))) {
    await interaction.reply({ content: 'Nur für Staff.', ephemeral: true });
    return;
  }
  const me = interaction.guild?.members.me;
  if (!me || !me.permissions.has(PermissionFlagsBits.ModerateMembers)) {
    await interaction.reply({ content: 'Bot fehlt ModerateMembers.', ephemeral: true });
    return;
  }
  const user = interaction.options.getUser('user', true);
  const minutes = interaction.options.getInteger('minutes', true);
  const reason = interaction.options.getString('reason', true);
  const member = await interaction.guild!.members.fetch(user.id).catch(() => null);
  if (!member) {
    await interaction.reply({ content: 'User ist nicht in der Guild.', ephemeral: true });
    return;
  }
  try {
    await member.timeout(minutes * 60_000, reason);
  } catch (e) {
    await interaction.reply({ content: `Fehler: ${(e as Error).message}`, ephemeral: true });
    return;
  }
  await logToStaffChannel(ctx, {
    title: 'Timeout',
    description: `<@${user.id}> (${user.tag})`,
    fields: [
      { name: 'Grund', value: reason },
      { name: 'Dauer', value: `${minutes} min` },
    ],
    footer: `von ${interaction.user.tag}`,
    color: 0xd9a13a,
  });
  await interaction.reply({
    embeds: [
      new EmbedBuilder()
        .setColor(0xd9a13a)
        .setTitle('Timed out')
        .setDescription(`<@${user.id}> — ${minutes} min — ${reason}`),
    ],
  });
}

async function execClear(interaction: ChatInputCommandInteraction, ctx: BotContext): Promise<void> {
  if (!(await isCallerStaff(interaction, ctx))) {
    await interaction.reply({ content: 'Nur für Staff.', ephemeral: true });
    return;
  }
  const me = interaction.guild?.members.me;
  if (!me || !me.permissions.has(PermissionFlagsBits.ManageMessages)) {
    await interaction.reply({ content: 'Bot fehlt ManageMessages.', ephemeral: true });
    return;
  }
  const count = interaction.options.getInteger('count', true);
  const fromUser = interaction.options.getUser('from_user', false);
  const channel = interaction.channel;
  if (!channel || !(channel instanceof TextChannel)) {
    await interaction.reply({ content: 'Channel unterstützt kein Bulk-Delete.', ephemeral: true });
    return;
  }
  await interaction.deferReply({ ephemeral: true });
  let messages = await channel.messages.fetch({ limit: 100 });
  if (fromUser) messages = messages.filter((m) => m.author.id === fromUser.id);
  const toDelete = [...messages.values()].slice(0, count);
  const deleted = await channel.bulkDelete(toDelete, true);
  await logToStaffChannel(ctx, {
    title: 'Clear',
    description: `${deleted.size} Nachricht${deleted.size === 1 ? '' : 'en'} in ${channel}`,
    fields: fromUser ? [{ name: 'Nur von', value: `<@${fromUser.id}>` }] : [],
    footer: `von ${interaction.user.tag}`,
    color: 0x6b4f9e,
  });
  await interaction.editReply(`${deleted.size} Nachrichten gelöscht.`);
}