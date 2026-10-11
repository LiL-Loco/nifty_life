/**
 * Who is this person, and which character do they speak as (ADR-0022).
 *
 * The binding is the three-table handshake from migration 009:
 *
 *   web_pairing_codes   game server only, no grant here - we cannot even read it
 *   web_link_requests   we INSERT (discord_id, code) and nothing else
 *   web_links           the proven binding, written by the game server
 *
 * We have no UPDATE anywhere, so we cannot confirm our own request. That is the
 * point: confirmation belongs to the game server alone.
 *
 * KNOWN WEAKNESS, carried over from `database/grants.sql`: `SELECT ON web_links`
 * returns every mapping, not just the caller's. The filter below is application
 * code rather than a privilege boundary. It is the one place in this codebase
 * where that is true, and it is written down rather than assumed safe.
 */
import 'server-only';

import { query, one } from './db';

export interface LinkedCharacter {
  characterId: string;
  discordId: string;
  linkedAt: string;
}

/**
 * The character this Discord account is bound to, or null.
 *
 * The `discord_id = ?` filter is applied in the query even though the grant
 * would return every row. Defence in depth costs nothing here.
 */
export async function linkedCharacter(discordId: string): Promise<LinkedCharacter | null> {
  if (!discordId) return null;

  return one<LinkedCharacter>(
    'SELECT discord_id, character_id, linked_at FROM web_links WHERE discord_id = ? LIMIT 1',
    [discordId],
  );
}

/**
 * The display name to publish under.
 *
 * The website has no grant on `characters` - that is deliberate, and it is why
 * posts snapshot their author's name. Until a post exists there is nothing to
 * snapshot, so this reads the name the game server already exposed through the
 * post feed rather than reaching for a table we are not allowed to read.
 */
export async function latestKnownName(
  discordId: string,
  characterId: string,
): Promise<string | null> {
  const row = await one<{ author_name: string }>(
    `SELECT author_name
       FROM peeper_posts
      WHERE author_character = ?
      ORDER BY created_at DESC
      LIMIT 1`,
    [characterId],
  );

  // discordId is intentionally unused here: it keeps the signature honest for
  // callers that have one, and makes it obvious that the name cannot be
  // attacker-supplied. It is derived from the session, never from a form.
  void discordId;

  return row?.author_name ?? null;
}

/**
 * Submit a pairing request.
 *
 * The code was generated in game and typed here. We store it and nothing else -
 * there is no follow-up write, because we have no UPDATE. The game server picks
 * the request up when it runs and proves the code by hashing it.
 *
 * Returns false only for an input we refuse outright. "Accepted but not yet
 * confirmed" is the normal state, not an error.
 */
export async function requestPairing(discordId: string, code: string): Promise<boolean> {
  if (!/^\d{5,32}$/.test(discordId)) return false;
  if (!/^[A-Za-z0-9]{4,16}$/.test(code)) return false;

  await query(
    'INSERT INTO web_link_requests (discord_id, code) VALUES (?, ?)',
    [discordId, code],
  );

  return true;
}

/** Requests this account has submitted, newest first. Useful for the status page. */
export async function pairingRequests(discordId: string, limit = 5) {
  return query<{ id: number; created_at: string }>(
    'SELECT id, created_at FROM web_link_requests WHERE discord_id = ? ORDER BY id DESC LIMIT ?',
    [discordId, limit],
  );
}