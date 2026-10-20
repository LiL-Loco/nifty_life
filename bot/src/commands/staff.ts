import { ChatInputCommandInteraction, EmbedBuilder, SlashCommandBuilder } from 'discord.js';

import type { Command } from './account.js';
import { isCallerStaff } from './account.js';

export const commands: Command[] = [
  {
    data: new SlashCommandBuilder().setName('staff').setDescription('List every Discord account mirrored into the staff table.'),
    staffOnly: true,
    execute: async (interaction, ctx) => {
    if (!(await isCallerStaff(interaction, ctx))) {
      await interaction.reply({ content: 'Nur für Staff.', ephemeral: true });
      return;
    }

    const rawRows = (await ctx.pool.execute(
      `SELECT discord_id, role_id, synced_at FROM staff ORDER BY synced_at DESC`,
    )) as unknown as { discord_id: string; role_id: string; synced_at: Date | string }[];
    const rows = rawRows.map((r) => ({
      ...r,
      synced_at: r.synced_at instanceof Date ? r.synced_at.toISOString() : String(r.synced_at),
    }));

    const embed = new EmbedBuilder()
      .setTitle(`Staff — ${rows.length}`)
      .setColor(0x6b4f9e)
      .setTimestamp(new Date());

    if (rows.length === 0) {
      embed.setDescription('Keine Staff-Member in der Mirror-Tabelle.');
    } else {
      const lines = await Promise.all(
        rows.map(async (row) => {
          let tag = row.discord_id;
          try {
            const member = await interaction.guild?.members.fetch(row.discord_id).catch(() => null);
            if (member) tag = `<@${row.discord_id}> (${member.user.tag})`;
          } catch {
            /* ignore */
          }
          return `• ${tag} — Rolle \`${row.role_id}\`, sync ${row.synced_at}`;
        }),
      );
      embed.setDescription(lines.join('\n'));
    }

    await interaction.reply({ embeds: [embed], ephemeral: true });
  },
  },
];

/** Used by /staff and other admin views to gate access. */
export const _isCallerStaff = async (i: ChatInputCommandInteraction, ctx: Parameters<typeof isCallerStaff>[1]) =>
  isCallerStaff(i, ctx);