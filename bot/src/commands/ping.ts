import { SlashCommandBuilder } from 'discord.js';

import type { Command, BotContext } from './account.js';

export const commands: Command[] = [
  {
    data: new SlashCommandBuilder().setName('ping').setDescription('Bot health check.'),
    execute: async (interaction, _ctx) => {
      const sent = Date.now();
      await interaction.reply({ content: 'pong…', ephemeral: true, fetchReply: true });
      const latency = Date.now() - sent;
      await interaction.editReply(`pong — ${latency}ms`);
    },
  },
];