/**
 * Slash commands for the bot.
 *
 * One file per command. `index.ts` registers them all and wires them to the
 * interaction event. Each command gets the `BotContext` (DB pool, guild, config)
 * and the interaction object; it returns an embed or text reply, never writes
 * directly to the interaction.
 */
import {
  ChatInputCommandInteraction,
  Client,
  EmbedBuilder,
  SlashCommandBuilder,
} from 'discord.js';
import type { Pool } from 'mysql2/promise';

/** What every command receives. */
export interface BotContext {
  client: Client;
  pool: Pool;
  guildId: string;
  staffChannelId?: string;
  webAdminUrl?: string;
}

/** One slash command. */
export interface Command {
  // The literal type narrows back to SlashCommandBuilder once subcommands /
  // options are attached; using `any` here lets every concrete builder fit
  // without a manual cast in every command file.
  data: any;
  /** Restrict to staff role IDs. Empty/undefined = public. */
  staffOnly?: boolean;
  execute(interaction: ChatInputCommandInteraction, ctx: BotContext): Promise<void>;
}

/** Helpers shared by commands. */

export async function isCallerStaff(
  interaction: ChatInputCommandInteraction,
  ctx: BotContext,
): Promise<boolean> {
  if (!interaction.guild || interaction.guild.id !== ctx.guildId) return false;
  const member = await interaction.guild.members
    .fetch(interaction.user.id)
    .catch(() => null);
  if (!member) return false;
  const { staffRoleIds } = await import('../config.js').then((m) => m.loadConfig());
  return member.roles.cache.some((role) => staffRoleIds.includes(role.id));
}

/** Coerce anything that might be a Date into an ISO string for an embed field. */
function asText(v: unknown): string {
  if (v == null) return 'nie';
  if (v instanceof Date) return v.toISOString();
  return String(v);
}

/** Read a row from `pool.execute` no matter which generic shape mysql2 chose. */
async function one<T>(pool: Pool, sql: string, params: any[]): Promise<T | null> {
  const [rows] = await pool.execute(sql, params as any);
  const arr = rows as unknown as T[];
  return arr[0] ?? null;
}

async function many<T>(pool: Pool, sql: string, params: any[]): Promise<T[]> {
  const [rows] = await pool.execute(sql, params as any);
  return rows as unknown as T[];
}

/** Read-only embed of a portal account, looked up by Discord user id. */
export async function accountEmbedByDiscord(
  ctx: BotContext,
  discordId: string,
): Promise<EmbedBuilder> {
  interface DiscordLinkRow {
    user_id: string;
    username: string;
  }
  interface PortalRow {
    id: string;
    email: string;
    username: string | null;
    email_verified_at: string | null;
    last_login_at: string | null;
    created_at: string;
  }
  interface StaffRow {
    role_id: string;
  }
  interface AccountRow {
    id: string;
    status: string;
  }
  interface CharRow {
    id: string;
    first_name: string;
    last_name: string;
  }

  const embed = new EmbedBuilder().setColor(0x6b4f9e).setTimestamp(new Date());

  const link = await one<DiscordLinkRow>(
    ctx.pool,
    `SELECT user_id, username FROM portal_user_discord WHERE discord_id = ? LIMIT 1`,
    [discordId],
  );
  if (!link) {
    return embed
      .setTitle(`Kein Portal-Account für <@${discordId}>`)
      .setDescription('Keine Verknüpfung zwischen Discord und Portal gefunden.')
      .setColor(0xc94f4f);
  }

  const portal = await one<PortalRow>(
    ctx.pool,
    `SELECT id, email, username, email_verified_at, last_login_at, created_at
       FROM portal_users WHERE id = ? LIMIT 1`,
    [link.user_id],
  );
  if (!portal) {
    return embed
      .setTitle(`Discord-Verknüpfung verwaist: <@${discordId}>`)
      .setDescription('Discord ist verknüpft, aber der Portal-User wurde gelöscht.')
      .setColor(0xc94f4f);
  }

  // Resolve the auxiliary facts. Account first (used as a precondition for
  // the characters query), then staff and characters together.
  const accountRow = await one<AccountRow>(
    ctx.pool,
    `SELECT id, status FROM accounts WHERE discord_id = ? LIMIT 1`,
    [discordId],
  );
  const [staffRow, characterRows] = await Promise.all([
    one<StaffRow>(ctx.pool, `SELECT role_id FROM staff WHERE discord_id = ? LIMIT 1`, [
      discordId,
    ]),
    accountRow
      ? many<CharRow>(
          ctx.pool,
          `SELECT id, first_name, last_name FROM characters WHERE account_id = ? ORDER BY created_at`,
          [accountRow.id],
        )
      : Promise.resolve([] as CharRow[]),
  ]);

  const statusLines: string[] = [];
  statusLines.push(`Staff: ${staffRow ? `✓ (\`${staffRow.role_id}\`)` : '✗'}`);
  statusLines.push(
    `Whitelist: ${accountRow ? `✓ (\`${accountRow.status}\`)` : '✗ (nicht beantragt)'}`,
  );
  if (characterRows.length > 0) {
    statusLines.push(
      `Charaktere: ${characterRows
        .map((c) => `\`${c.first_name} ${c.last_name}\` (\`${c.id.slice(0, 8)}…\`)`)
        .join(', ')}`,
    );
  } else {
    statusLines.push('Charaktere: keine');
  }

  return embed
    .setTitle(`Portal: ${portal.email}`)
    .addFields(
      { name: 'ID', value: `\`${portal.id}\``, inline: true },
      { name: 'Username', value: portal.username ?? '—', inline: true },
      { name: 'E-Mail bestätigt', value: portal.email_verified_at ? '✓ ja' : '✗ nein', inline: true },
      { name: 'Erstellt', value: asText(portal.created_at), inline: true },
      { name: 'Letzter Login', value: asText(portal.last_login_at), inline: true },
      {
        name: 'Discord',
        value: `<@${discordId}> (\`${link.username}\`, ID \`${discordId}\`)`,
        inline: false,
      },
      { name: 'Status', value: statusLines.join('\n'), inline: false },
    );
}

/** Read-only embed of a character. */
export async function characterEmbed(ctx: BotContext, characterId: string): Promise<EmbedBuilder> {
  interface CharFullRow {
    id: string;
    account_id: string;
    first_name: string;
    last_name: string;
    gender: string;
    date_of_birth: string;
    birthplace: string;
    created_at: string;
  }
  const row = await one<CharFullRow>(
    ctx.pool,
    `SELECT id, account_id, first_name, last_name, gender, date_of_birth, birthplace, created_at
       FROM characters WHERE id = ? LIMIT 1`,
    [characterId],
  );

  const embed = new EmbedBuilder().setColor(0x6b4f9e).setTimestamp(new Date());
  if (!row) {
    return embed.setTitle(`Kein Charakter für ${characterId}`).setColor(0xc94f4f);
  }
  return embed
    .setTitle(`${row.first_name} ${row.last_name}`)
    .addFields(
      { name: 'ID', value: `\`${row.id}\``, inline: true },
      { name: 'Account', value: `\`${row.account_id}\``, inline: true },
      { name: 'Geschlecht', value: row.gender, inline: true },
      { name: 'Geburtsdatum', value: String(row.date_of_birth).slice(0, 10), inline: true },
      { name: 'Geburtsort', value: row.birthplace, inline: true },
      { name: 'Erstellt', value: asText(row.created_at), inline: true },
    );
}

/** The /account and /char slash commands. */

export const commands: Command[] = [
  {
    data: new SlashCommandBuilder()
      .setName('account')
      .setDescription('Portal-Account-Details. Default: dein eigener Discord-Account.')
      .addStringOption((o) =>
        o
          .setName('user_id')
          .setDescription('Discord-ID (17-20 Ziffern). Ohne: dein eigener Account.')
          .setRequired(false)
          .setMinLength(17)
          .setMaxLength(20),
      ),
    execute: async (interaction, ctx) => {
      const rawId = (interaction.options.data ?? []).find((o) => o.name === 'user_id')?.value as
        | string
        | undefined;

      let lookupDiscordId: string;
      if (rawId && /^\d{17,20}$/.test(rawId)) {
        const callerIsStaff = await isCallerStaff(interaction, ctx);
        if (!callerIsStaff && rawId !== interaction.user.id) {
          await interaction.reply({
            content: 'Nur Staff darf andere Accounts abfragen.',
            ephemeral: true,
          });
          return;
        }
        lookupDiscordId = rawId;
      } else {
        lookupDiscordId = interaction.user.id;
      }

      await interaction.deferReply({ ephemeral: true });
      await interaction.editReply({ embeds: [await accountEmbedByDiscord(ctx, lookupDiscordId)] });
    },
  },
  {
    data: new SlashCommandBuilder()
      .setName('char')
      .setDescription('Charakter-Details.')
      .addStringOption((o) =>
        o
          .setName('id')
          .setDescription('Character-ID (UUID).')
          .setRequired(true)
          .setMinLength(36)
          .setMaxLength(36),
      ),
    execute: async (interaction, ctx) => {
      const id = interaction.options.getString('id', true);
      await interaction.deferReply({ ephemeral: true });
      await interaction.editReply({ embeds: [await characterEmbed(ctx, id)] });
    },
  },
];