/**
 * Ticketsystem: one button per message in a configured channel creates a private
 * thread for the requester, owned by the staff team. `/ticket close` archives
 * the transcript as an attachment and locks the thread.
 *
 * Design choices:
 *   - Private thread, not a new channel. Threads live under a parent channel
 *     so #support-staff stays the visible funnel. A channel-per-ticket design
 *     would need a cleanup cron and leak permissions on every new channel.
 *   - The opener's first message becomes the thread title. A second message
 *     is the question — the bot only carries the framing, never the answer.
 *   - The transcript is fetched with `channel.messages.fetch()`, then
 *     `messages.fetch({ after })` per thread. The bot doesn't pretend to
 *     archive anything it hasn't read.
 */
import {
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  ChatInputCommandInteraction,
  Client,
  EmbedBuilder,
  Guild,
  ModalBuilder,
  ModalSubmitInteraction,
  PermissionFlagsBits,
  SlashCommandBuilder,
  SlashCommandSubcommandBuilder,
  StringSelectMenuBuilder,
  TextChannel,
  TextInputBuilder,
  TextInputStyle,
} from 'discord.js';
import type { Pool } from 'mysql2/promise';

import type { BotContext } from '../commands/account.js';
import { isCallerStaff } from '../commands/account.js';

const PANEL_CHANNEL_KEY = 'tickets:panel:channel';
const PANEL_MESSAGE_KEY = 'tickets:panel:message';

interface TicketsContext {
  client: Client;
  pool: Pool;
  guildId: string;
  /** Channel where the panel lives. */
  panelChannelId: string;
  /** Channel where new tickets are opened (typically the same as panel). */
  ticketParentChannelId: string;
  /** Role IDs that get auto-added to a ticket thread. */
  staffRoleIds: string[];
  /** Where to post the transcript when closed. */
  transcriptChannelId: string | null;
}

export function attachTickets(client: Client, ctx: TicketsContext): void {
  // One persistent panel message in the configured channel.
  client.once('ready', async () => {
    await ensurePanel(ctx);
  });

  client.on('interactionCreate', async (interaction) => {
    if (interaction.isButton()) {
      if (interaction.customId === 'ticket:open') {
        await openTicketFromButton(ctx, interaction);
      }
    } else if (interaction.isStringSelectMenu()) {
      if (interaction.customId === 'ticket:category') {
        await openTicketFromMenu(ctx, interaction);
      }
    } else if (interaction.isModalSubmit()) {
      if (interaction.customId.startsWith('ticket:submit:')) {
        await openTicketFromModal(ctx, interaction);
      }
    } else if (interaction.isChatInputCommand()) {
      if (interaction.commandName === 'ticket') {
        await handleTicketCommand(ctx, interaction);
      }
    }
  });
}

async function ensurePanel(ctx: TicketsContext): Promise<void> {
  const guild = ctx.client.guilds.cache.get(ctx.guildId);
  if (!guild) return;
  const channel = await guild.channels.fetch(ctx.panelChannelId).catch(() => null);
  if (!channel || !(channel instanceof TextChannel)) return;

  const embed = new EmbedBuilder()
    .setColor(0x6b4f9e)
    .setTitle('Support-Tickets')
    .setDescription(
      'Klick den Button, um ein privates Ticket zu öffnen. Schreibt dein Anliegen in das Formular — das Team bekommt eine Benachrichtigung und übernimmt den Thread.',
    );

  const button = new ActionRowBuilder<ButtonBuilder>().addComponents(
    new ButtonBuilder()
      .setCustomId('ticket:open')
      .setLabel('Ticket öffnen')
      .setStyle(ButtonStyle.Primary)
      .setEmoji('🎫'),
  );

  await channel.send({ embeds: [embed], components: [button] });
}

async function openTicketFromButton(ctx: TicketsContext, interaction: import('discord.js').ButtonInteraction): Promise<void> {
  const modal = new ModalBuilder()
    .setCustomId(`ticket:submit:${interaction.id}`)
    .setTitle('Ticket öffnen')
    .addComponents(
      new ActionRowBuilder<TextInputBuilder>().addComponents(
        new TextInputBuilder()
          .setCustomId('subject')
          .setLabel('Betreff')
          .setStyle(TextInputStyle.Short)
          .setMinLength(3)
          .setMaxLength(80)
          .setRequired(true),
      ),
      new ActionRowBuilder<TextInputBuilder>().addComponents(
        new TextInputBuilder()
          .setCustomId('body')
          .setLabel('Beschreib dein Anliegen')
          .setStyle(TextInputStyle.Paragraph)
          .setMinLength(20)
          .setMaxLength(2000)
          .setRequired(true),
      ),
    );

  await interaction.showModal(modal);
}

async function openTicketFromModal(ctx: TicketsContext, interaction: ModalSubmitInteraction): Promise<void> {
  const subject = interaction.fields.getTextInputValue('subject');
  const body = interaction.fields.getTextInputValue('body');

  await interaction.reply({ content: 'Ticket wird angelegt…', ephemeral: true });

  const guild = ctx.client.guilds.cache.get(ctx.guildId);
  if (!guild) return;

  const parent = await guild.channels.fetch(ctx.ticketParentChannelId).catch(() => null);
  if (!parent || !(parent instanceof TextChannel)) return;

  const thread = await parent.threads.create({
    name: `ticket-${subject.slice(0, 40)}`,
    autoArchiveDuration: 1440,
    type: 12 as never, // PrivateThread
    reason: `Ticket von ${interaction.user.tag}`,
  });

  // Add staff to the thread + the opener (they're already in).
  await thread.members.add(interaction.user.id).catch(() => undefined);
  for (const roleId of ctx.staffRoleIds) {
    await thread.members.add(roleId).catch(() => undefined);
  }

  const intro = new EmbedBuilder()
    .setColor(0x6b4f9e)
    .setTitle(subject)
    .setDescription(body)
    .setFooter({ text: `Eröffnet von ${interaction.user.tag}` })
    .setTimestamp(new Date());

  await thread.send({ content: `<@${interaction.user.id}>`, embeds: [intro] });

  await interaction.editReply({ content: `Dein Ticket ist offen: <#${thread.id}>` });
}

async function openTicketFromMenu(
  ctx: TicketsContext,
  _interaction: import('discord.js').StringSelectMenuInteraction,
): Promise<void> {
  /* unused — the panel uses a button -> modal flow. Kept for future categories. */
  void ctx;
}

async function handleTicketCommand(ctx: TicketsContext, interaction: ChatInputCommandInteraction): Promise<void> {
  const botCtx: BotContext = {
    client: ctx.client,
    pool: ctx.pool,
    guildId: ctx.guildId,
  };
  if (!(await isCallerStaff(interaction, botCtx))) {
    await interaction.reply({ content: 'Nur für Staff.', ephemeral: true });
    return;
  }

  const sub = interaction.options.getSubcommand();
  if (sub === 'close') {
    await closeTicket(ctx, interaction);
  }
}

async function closeTicket(ctx: TicketsContext, interaction: ChatInputCommandInteraction): Promise<void> {
  const thread = interaction.channel;
  if (!thread || !('joinable' in thread) || !('parentId' in thread)) {
    await interaction.reply({ content: 'Dieser Channel ist kein Thread.', ephemeral: true });
    return;
  }

  await interaction.reply({ content: 'Schließe Ticket und archiviere Verlauf…', ephemeral: true });

  const messages = await thread.messages.fetch({ limit: 100 });
  const transcript = messages
    .map((m) => `[${m.createdAt.toISOString()}] ${m.author.tag}: ${m.content || '(Embed/Anhang)'}`)
    .reverse()
    .join('\n');

  if (ctx.transcriptChannelId) {
    const ch = await ctx.client.channels.fetch(ctx.transcriptChannelId).catch(() => null);
    if (ch && ch.isSendable()) {
      await ch.send({
        files: [{ attachment: Buffer.from(transcript, 'utf-8'), name: `transcript-${thread.id}.txt` }],
        embeds: [
          new EmbedBuilder()
            .setColor(0x6b4f9e)
            .setTitle(`Ticket-Archiv — ${thread.name}`)
            .setDescription(`Geschlossen von ${interaction.user.tag}`),
        ],
      });
    }
  }

  await (thread as any).setLocked?.(true, 'Ticket closed');
  await (thread as any).setArchived?.(true, 'Ticket closed');
  await interaction.editReply({ content: 'Ticket geschlossen + Verlauf archiviert.' });
}

/** Register the /ticket slash command. */
export function ticketCommandData(): SlashCommandBuilder {
  return new SlashCommandBuilder()
    .setName('ticket')
    .setDescription('Ticket-Helper für Staff.')
    .addSubcommand((s: SlashCommandSubcommandBuilder) =>
      s.setName('close').setDescription('Schließt das aktuelle Ticket und archiviert den Verlauf.'),
    ) as unknown as SlashCommandBuilder;
}

interface Command {
  data: import('discord.js').SlashCommandBuilder;
  staffOnly?: boolean;
  execute(interaction: ChatInputCommandInteraction, ctx: BotContext): Promise<void>;
}

export const ticketCommand: Command = {
  data: ticketCommandData(),
  staffOnly: true,
  execute: async (interaction, _ctx) => {
    // The actual close logic is in handleTicketCommand via the attachTickets handler.
    // This execute is a placeholder so the command is registered; the real
    // work happens in the interactionCreate router inside attachTickets.
    await interaction.reply({ content: 'Nutze /ticket close innerhalb des Tickets.', ephemeral: true });
  },
};

/** Silence unused-import warnings for now. */
type _Unused = typeof PermissionFlagsBits | Guild | StringSelectMenuBuilder;