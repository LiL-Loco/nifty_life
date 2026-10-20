import { ChatInputCommandInteraction, EmbedBuilder, SlashCommandBuilder } from 'discord.js';

import type { BotContext, Command } from './account.js';
import { isCallerStaff } from './account.js';

export const commands: Command[] = [
  {
    data: new SlashCommandBuilder()
      .setName('whitelist')
      .setDescription('Manage FiveM whitelist (accounts.status).')
      .addSubcommand((s) =>
        s
          .setName('add')
          .setDescription('Whitelist a Discord user for FiveM connect.')
          .addUserOption((o) => o.setName('user').setDescription('Discord user.').setRequired(true)),
      )
      .addSubcommand((s) =>
        s
          .setName('remove')
          .setDescription('Suspend a Discord user (sets status=suspended).')
          .addUserOption((o) => o.setName('user').setDescription('Discord user.').setRequired(true)),
      )
      .addSubcommand((s) =>
        s
          .setName('status')
          .setDescription('Show a user’s whitelist status.')
          .addUserOption((o) => o.setName('user').setDescription('Discord user.').setRequired(true)),
      ),
    staffOnly: true,
    execute: async (interaction, ctx) => {
      if (!(await isCallerStaff(interaction, ctx))) {
        await interaction.reply({ content: 'Nur für Staff.', ephemeral: true });
        return;
      }

      const sub = interaction.options.getSubcommand();
      const user = interaction.options.getUser('user', true);

      if (sub === 'add') {
        const [existingRows] = await ctx.pool.execute(
          `SELECT id FROM accounts WHERE discord_id = ? LIMIT 1`,
          [user.id],
        );
        const existing = (existingRows as { id: string }[])[0];
        if (existing) {
          await ctx.pool.execute(
            `UPDATE accounts SET status = 'active', updated_at = NOW() WHERE id = ?`,
            [existing.id],
          );
        } else {
          await ctx.pool.execute(
            `INSERT INTO accounts (id, discord_id, status) VALUES (UUID(), ?, 'active')`,
            [user.id],
          );
        }
        await logToStaffChannel(ctx, {
          title: 'Whitelist hinzugefügt',
          description: `<@${user.id}> (${user.tag})`,
          footer: `von ${interaction.user.tag}`,
          color: 0x6bbf6b,
        });
        await interaction.reply({
          embeds: [
            new EmbedBuilder()
              .setColor(0x6bbf6b)
              .setTitle('Whitelisted')
              .setDescription(`<@${user.id}> darf jetzt connecten.`),
          ],
          ephemeral: true,
        });
        return;
      }

      if (sub === 'remove') {
        const [result] = await ctx.pool.execute(
          `UPDATE accounts SET status = 'suspended', updated_at = NOW() WHERE discord_id = ?`,
          [user.id],
        );
        const affected = (result as { affectedRows: number }).affectedRows;
        await logToStaffChannel(ctx, {
          title: 'Whitelist entzogen',
          description: `<@${user.id}> (${user.tag})`,
          footer: `von ${interaction.user.tag}`,
          color: 0xc94f4f,
        });
        await interaction.reply({
          embeds: [
            new EmbedBuilder()
              .setColor(0xc94f4f)
              .setTitle('Suspended')
              .setDescription(
                affected > 0
                  ? `<@${user.id}> wurde auf \`suspended\` gesetzt.`
                  : `<@${user.id}> war nicht gewhitelisted (no-op).`,
              ),
          ],
          ephemeral: true,
        });
        return;
      }

      if (sub === 'status') {
        const [rows] = await ctx.pool.execute(
          `SELECT id, discord_id, status FROM accounts WHERE discord_id = ? LIMIT 1`,
          [user.id],
        );
        const row = (rows as { id: string; status: string }[])[0];
        const embed = new EmbedBuilder().setColor(0x6b4f9e).setTimestamp(new Date());
        if (!row) {
          embed
            .setTitle(`Whitelist-Status: ${user.tag}`)
            .setDescription('Nicht in `accounts` enthalten — kein Zugang zum FiveM-Server.');
        } else {
          embed
            .setTitle(`Whitelist-Status: ${user.tag}`)
            .addFields(
              { name: 'Account-ID', value: `\`${row.id}\``, inline: true },
              { name: 'Status', value: `\`${row.status}\``, inline: true },
            );
        }
        await interaction.reply({ embeds: [embed], ephemeral: true });
        return;
      }
    },
  },
];

interface LogFields {
  title: string;
  description: string;
  fields?: { name: string; value: string }[];
  footer?: string;
  color?: number;
}

export async function logToStaffChannel(ctx: BotContext, f: LogFields): Promise<void> {
  const channelId = ctx.staffChannelId;
  if (!channelId) return;
  const channel = await ctx.client.channels.fetch(channelId).catch(() => null);
  if (!channel || !channel.isSendable()) return;
  const embed = new EmbedBuilder()
    .setTitle(f.title)
    .setDescription(f.description)
    .setColor(f.color ?? 0x6b4f9e)
    .setTimestamp(new Date());
  if (f.fields && f.fields.length > 0) embed.addFields(...f.fields);
  if (f.footer) embed.setFooter({ text: f.footer });
  await channel.send({ embeds: [embed] });
}