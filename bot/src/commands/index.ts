/**
 * Command registry: loads every commands/*.ts file, registers the slash-command
 * builders against the guild, and dispatches incoming interactions.
 */
import { Client, Interaction, REST, Routes } from 'discord.js';
import type { Pool } from 'mysql2/promise';

import { commands as accountCommands } from './account.js';
import { commands as staffCommands } from './staff.js';
import { commands as whitelistCommands } from './whitelist.js';
import { commands as modCommands } from './mod.js';
import { commands as pingCommands } from './ping.js';
import type { BotContext, Command } from './account.js';

export type { BotContext, Command };

const ALL_COMMANDS: Command[] = [
  ...accountCommands,
  ...staffCommands,
  ...whitelistCommands,
  ...modCommands,
  ...pingCommands,
];

export function getAllCommands(): Command[] {
  return ALL_COMMANDS;
}

export async function registerCommands(client: Client, guildId: string): Promise<void> {
  const rest = new REST({ version: '10' }).setToken(client.token!);
  const body = ALL_COMMANDS.map((c) => c.data.toJSON());

  // Guild-scoped registration: instant propagation, no global-rate-limit worries.
  await rest.put(Routes.applicationGuildCommands(client.user!.id, guildId), { body });

  console.log(`[commands] registered ${body.length} slash command(s) for guild ${guildId}`);
}

export function buildContext(client: Client, pool: Pool, guildId: string, opts: {
  staffChannelId?: string;
  webAdminUrl?: string;
}): BotContext {
  return { client, pool, guildId, ...opts };
}

export function attachInteractionHandler(client: Client): void {
  // Low-level handler: discord.js's ChatInputCommand.parse() re-validates the
  // interaction options against the registered schema and crashes on the
  // auto-attached member.joined_at field (it's a Date, but our schema expects
  // a string). We patch the raw payload before discord.js touches it.
  client.on('interactionCreate', async (interaction: Interaction) => {
    if (!interaction.isChatInputCommand()) return;

    const cmd = ALL_COMMANDS.find((c) => c.data.name === interaction.commandName);
    if (!cmd) return;

    const pool = (client as unknown as { __nifty_pool?: Pool }).__nifty_pool;
    if (!pool) {
      await interaction
        .reply({ content: 'Bot ist noch nicht bereit.', ephemeral: true })
        .catch(() => undefined);
      return;
    }

    const ctx: BotContext = {
      client,
      pool,
      guildId: (client as unknown as { __nifty_guildId?: string }).__nifty_guildId ?? '',
      staffChannelId: (client as unknown as { __nifty_staffChannelId?: string })
        .__nifty_staffChannelId,
      webAdminUrl: (client as unknown as { __nifty_webAdminUrl?: string }).__nifty_webAdminUrl,
    };

    try {
      await cmd.execute(interaction, ctx);
    } catch (err) {
      console.error(`[commands] ${interaction.commandName} failed:`, err);
      if (interaction.deferred || interaction.replied) {
        await interaction
          .editReply({ content: 'Etwas ist schiefgelaufen — siehe Logs.' })
          .catch(() => undefined);
      } else {
        await interaction
          .reply({ content: 'Etwas ist schiefgelaufen — siehe Logs.', ephemeral: true })
          .catch(() => undefined);
      }
    }
  });

  // Same, but at the raw gateway frame level — strip member.joined_at (a Date)
  // from the interaction payload before discord.js's schema validator sees it.
  client.on('raw', (packet) => {
    if (packet.t !== 'INTERACTION_CREATE') return;
    const d = packet.d;
    if (!d || d.type !== 2 /* CHAT_INPUT */) return;
    const data = d.data;
    if (!data || !Array.isArray(data.options)) return;
    // Convert Date -> ISO string in any string-typed option that has a Date.
    // discord.js's schema validator expects a string primitive; Date slips
    // through the wire as an object.
    for (const opt of data.options) {
      if (opt && opt.value instanceof Date) opt.value = opt.value.toISOString();
    }
    // Same for resolved entities (member.premium_since etc.) — these come back
    // as Date objects from the gateway. We don't use them in commands so the
    // safest fix is to coerce every Date-typed field to an ISO string.
    if (data.resolved) {
      for (const key of Object.keys(data.resolved)) {
        const bucket = data.resolved[key];
        if (bucket && typeof bucket === 'object') {
          for (const id of Object.keys(bucket)) {
            const ent = bucket[id];
            if (!ent) continue;
            for (const field of Object.keys(ent)) {
              if (ent[field] instanceof Date) ent[field] = (ent[field] as Date).toISOString();
            }
          }
        }
      }
    }
  });
}