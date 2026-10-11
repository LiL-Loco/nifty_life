/**
 * Peeper on the web (ADR-0022).
 *
 * A post is authored by a CHARACTER, on any surface. There is no separate web
 * identity, because two identities would mean a deletion in game that reappears
 * on the web under an identity moderation cannot tie to the first one.
 *
 * The important mechanic is in `createPost`: the author is resolved from
 * `web_links` for the SESSION's Discord ID, inside the same transaction as the
 * insert. `peeper_posts.author_character` is a plain column with nothing
 * constraining it, so the guarantee lives here - and `database/grants.sql`
 * records that gap in exactly these words.
 *
 * Deletes: there is none for a PLAYER, and there never will be. `nifty_website`
 * has no DELETE and no UPDATE on `peeper_posts`. The moderation team can soft-
 * delete through the admin connection and nothing more (migrations 012/013):
 * the row stays, hidden by `deleted_at`, carrying who removed it and why.
 *
 * Two kinds of author exist since migration 012: a character (players) or a
 * Discord account (the team). Never neither, never both — a CHECK constraint in
 * the database holds that, not this file.
 */
import 'server-only';

import { one, query, transaction, newUuid, adminQuery, adminSoftDeletePost } from './db';

export interface Post {
  id: string;
  /** NULL for a staff post — see migration 012. */
  author_character: string | null;
  /** Set for a staff post, NULL for a character post. */
  author_discord_id: string | null;
  author_name: string;
  parent_id: string | null;
  body: string;
  place_name: string | null;
  source: 'game' | 'web' | 'staff';
  created_at: string;
  deleted_at?: string | null;
}

export interface FeedPost extends Post {
  like_count: number;
  reply_count: number;
}

const MAX_BODY = 500;
const MAX_PLACE = 64;

/**
 * Control characters and DEL, written as escapes rather than literal bytes.
 * A raw NUL in a source file makes it binary to every tool that touches it, and
 * one stray byte is enough to terminate a command line.
 */
const CONTROL_CHARS = /[\x00-\x1F\x7F]/;

/**
 * The public feed.
 *
 * `deleted_at IS NULL` is the whole of the moderation model on this surface: the
 * game server soft-deletes, and because we cannot UPDATE we cannot resurrect a
 * post either.
 */
export async function feed(limit = 30, before?: string): Promise<FeedPost[]> {
  const safeLimit = Math.min(Math.max(Number(limit) || 30, 1), 100);

  return query<FeedPost>(
    `SELECT p.id, p.author_character, p.author_discord_id, p.author_name, p.parent_id,
            p.body, p.place_name, p.source, p.created_at,
            (SELECT COUNT(*) FROM peeper_likes l WHERE l.post_id = p.id) AS like_count,
            (SELECT COUNT(*) FROM peeper_posts r
              WHERE r.parent_id = p.id AND r.deleted_at IS NULL) AS reply_count
       FROM peeper_posts p
      WHERE p.deleted_at IS NULL
        AND p.parent_id IS NULL
        AND (? IS NULL OR p.created_at < ?)
      ORDER BY p.created_at DESC
      LIMIT ${safeLimit}`,
    [before ?? null, before ?? null],
  );
}

/** Replies to one post. Same visibility rule as the feed. */
export async function replies(postId: string): Promise<Post[]> {
  return query<Post>(
    `SELECT id, author_character, author_discord_id, author_name, parent_id, body,
            place_name, source, created_at
       FROM peeper_posts
      WHERE parent_id = ? AND deleted_at IS NULL
      ORDER BY created_at ASC
      LIMIT 100`,
    [postId],
  );
}

export type WriteResult = { ok: true; id: string } | { ok: false; error: string };

/**
 * Publish a post as this account's linked character.
 *
 * The author is never taken from the request. It is looked up through
 * `web_links` for the session's Discord ID, in the same transaction as the
 * insert - so a caller cannot post as someone else even by guessing a UUID.
 *
 * `author_name` is snapshotted onto the row, which is what lets this surface
 * render a feed with no grant at all on `characters`.
 */
export async function createPost(
  discordId: string,
  body: string,
  placeName: string | null,
  parentId: string | null,
): Promise<WriteResult> {
  const text = body.trim();
  if (!text || text.length > MAX_BODY) {
    return { ok: false, error: `Ein Beitrag muss zwischen 1 und ${MAX_BODY} Zeichen lang sein.` };
  }
  if (CONTROL_CHARS.test(text)) {
    return { ok: false, error: 'Ein Beitrag darf keine Steuerzeichen enthalten.' };
  }

  const place = placeName?.trim() || null;
  if (place && (place.length > MAX_PLACE || CONTROL_CHARS.test(place))) {
    return { ok: false, error: 'Dieser Ortsname ist nicht verwendbar.' };
  }

  const parent = parentId ?? null;
  if (parent && !/^[0-9a-f-]{36}$/.test(parent)) {
    return { ok: false, error: 'Unbekannter Beitrag.' };
  }

  const id = newUuid();

  try {
    await transaction(async (conn) => {
      const [linkRows] = await conn.execute<any[]>(
        'SELECT character_id FROM web_links WHERE discord_id = ? LIMIT 1',
        [discordId],
      );

      const characterId = linkRows[0]?.character_id as string | undefined;
      if (!characterId) {
        throw new NotLinkedError();
      }

      // The name comes from the character's most recent post, because this
      // account has no grant on `characters`. A character that has never posted
      // has no published name, and inventing one here would be worse than
      // asking the player to post from the game first.
      const [nameRows] = await conn.execute<any[]>(
        `SELECT author_name FROM peeper_posts
          WHERE author_character = ?
          ORDER BY created_at DESC LIMIT 1`,
        [characterId],
      );

      const authorName = nameRows[0]?.author_name as string | undefined;
      if (!authorName) {
        throw new UnnamedCharacterError();
      }

      if (parent) {
        const [parentRows] = await conn.execute<any[]>(
          'SELECT id FROM peeper_posts WHERE id = ? AND deleted_at IS NULL LIMIT 1',
          [parent],
        );
        if (parentRows.length === 0) {
          throw new UnknownPostError();
        }
      }

      await conn.execute(
        `INSERT INTO peeper_posts (id, author_character, author_name, parent_id, body, place_name, source)
         VALUES (?, ?, ?, ?, ?, ?, 'web')`,
        [id, characterId, authorName, parent, text, place],
      );
    });
  } catch (error) {
    if (error instanceof NotLinkedError) {
      return { ok: false, error: 'Verknüpfe deinen Charakter im Spiel, bevor du hier schreibst.' };
    }
    if (error instanceof UnnamedCharacterError) {
      return {
        ok: false,
        error:
          'Dein Charakter hat noch keinen veröffentlichten Namen. Schreib zuerst einen Beitrag im Spiel.',
      };
    }
    if (error instanceof UnknownPostError) {
      return { ok: false, error: 'Dieser Beitrag existiert nicht mehr.' };
    }
    return { ok: false, error: 'Das konnte nicht veröffentlicht werden. Bitte versuch es noch einmal.' };
  }

  return { ok: true, id };
}

class NotLinkedError extends Error {}
class UnnamedCharacterError extends Error {}
class UnknownPostError extends Error {}

/**
 * ============================================================
 * Moderation-team surface (migrations 012/013).
 *
 * Everything below runs on the ADMIN connection. `nifty_website` has no INSERT
 * on `peeper_posts` for a staff author and no UPDATE on the delete columns at
 * all, so none of this is reachable from the public pool even by accident.
 *
 * The team publishes under their Discord ID, not a character: a moderator who
 * has never played the game still writes here, and still leaves an attributable
 * author behind.
 * ============================================================
 */

/**
 * Publish as the moderation team.
 *
 * `name` is the Discord display name from the SIGNED session, never from the
 * form — a moderator should not be able to post an announcement signed with
 * somebody else's name, not even their own surname.
 */
export async function staffPost(
  discordId: string,
  name: string,
  body: string,
  placeName: string | null,
): Promise<WriteResult> {
  if (!/^\d{5,32}$/.test(discordId)) {
    return { ok: false, error: 'Deine Sitzung ist ungültig.' };
  }

  const text = body.trim();
  if (!text || text.length > MAX_BODY) {
    return { ok: false, error: `Ein Beitrag muss zwischen 1 und ${MAX_BODY} Zeichen lang sein.` };
  }
  if (CONTROL_CHARS.test(text)) {
    return { ok: false, error: 'Ein Beitrag darf keine Steuerzeichen enthalten.' };
  }

  const displayName = name.trim();
  if (!displayName || displayName.length > 129 || CONTROL_CHARS.test(displayName)) {
    return { ok: false, error: 'Dein Anzeigename ist nicht verwendbar.' };
  }

  const place = placeName?.trim() || null;
  if (place && (place.length > MAX_PLACE || CONTROL_CHARS.test(place))) {
    return { ok: false, error: 'Dieser Ortsname ist nicht verwendbar.' };
  }

  const id = newUuid();

  try {
    // author_character stays NULL. The CHECK constraint in migration 012 is what
    // makes that legal rather than accidental — a row with neither identity is
    // rejected by the database.
    await adminQuery(
      `INSERT INTO peeper_posts
         (id, author_character, author_discord_id, author_name, parent_id, body, place_name, source)
       VALUES (?, NULL, ?, ?, NULL, ?, ?, 'staff')`,
      [id, discordId, displayName, text, place],
    );
  } catch {
    return { ok: false, error: 'Das konnte nicht veröffentlicht werden. Bitte versuch es noch einmal.' };
  }

  return { ok: true, id };
}

/**
 * Soft-delete a post.
 *
 * SOFT, and that is the whole design. No account in this project holds DELETE on
 * `peeper_posts`: the row stays, `deleted_at` hides it from the feed, and
 * `deleted_by_discord_id` plus `deleted_reason` record who removed it and why.
 * Three months later somebody asks why a comment vanished, and the answer exists.
 *
 * Already-deleted posts are not touched, so the first reason recorded is the one
 * kept — a later moderator cannot overwrite the record of the first decision.
 */
export async function staffDeletePost(
  postId: string,
  staffDiscordId: string,
  reason: string | null,
): Promise<WriteResult> {
  if (!/^[0-9a-f-]{36}$/.test(postId)) {
    return { ok: false, error: 'Unbekannter Beitrag.' };
  }
  if (!/^\d{5,32}$/.test(staffDiscordId)) {
    return { ok: false, error: 'Deine Sitzung ist ungültig.' };
  }

  const note = reason?.trim() || null;
  if (note && (note.length > 255 || CONTROL_CHARS.test(note))) {
    return { ok: false, error: 'Der Löschgrund ist zu lang oder unbrauchbar.' };
  }

  const affected = await adminSoftDeletePost(postId, {
    deleted_at: new Date().toISOString().slice(0, 19).replace('T', ' '),
    deleted_by_discord_id: staffDiscordId,
    deleted_reason: note,
  });

  if (affected === 0) {
    return { ok: false, error: 'Dieser Beitrag existiert nicht mehr oder ist bereits gelöscht.' };
  }

  return { ok: true, id: postId };
}

/**
 * Like as the moderation team.
 *
 * Returns false when the post was already liked, which is the desired end state
 * rather than an error — same contract as `likePost`.
 */
export async function staffLike(discordId: string, postId: string): Promise<boolean> {
  try {
    await adminQuery(
      `INSERT INTO peeper_likes (post_id, author_discord_id) VALUES (?, ?)`,
      [postId, discordId],
    );
    return true;
  } catch {
    // The trigger on `actor` makes the duplicate a duplicate-key violation, so
    // this catch is the "already liked" path and nothing else can be silently
    // swallowed here: a genuine failure returns false to the same caller, and the
    // UI treats a false as "not liked now", which is never a lie.
    return false;
  }
}

/** Unlike as the moderation team. The mirror of `staffLike`. */
export async function staffUnlike(discordId: string, postId: string): Promise<boolean> {
  await adminQuery('DELETE FROM peeper_likes WHERE post_id = ? AND author_discord_id = ?', [
    postId,
    discordId,
  ]);
  return true;
}

/**
 * File a report as the moderation team, against a player's post.
 */
export async function staffReport(
  discordId: string,
  postId: string,
  reason: string,
): Promise<WriteResult> {
  if (!REASONS.includes(reason as ReportReason)) {
    return { ok: false, error: 'Unbekannter Grund.' };
  }

  const id = newUuid();

  try {
    await adminQuery(
      `INSERT INTO peeper_reports (id, reporter, reporter_discord_id, post_id, reason)
       VALUES (?, NULL, ?, ?, ?)`,
      [id, discordId, postId, reason],
    );
  } catch {
    return { ok: false, error: 'Die Meldung konnte nicht übermittelt werden.' };
  }

  return { ok: true, id };
}

// KNOWN GAP, stated rather than half-built: nobody can RESOLVE a report.
// `peeper_reports.status` moves to 'actioned' or 'dismissed' only by the game
// server (ADR-0019), and no web account holds UPDATE on that table — including
// nifty_admin, deliberately. A moderator can therefore see and delete the post
// a report points at, but the report row itself stays 'open'. Whoever resolves
// them does it in game. Closing this means granting the admin account a
// column-scoped UPDATE on status/resolved_at/resolution_note; that is a real
// decision, not a leftover, and it is not made here.
export async function likePost(characterId: string, postId: string): Promise<boolean> {
  try {
    await query('INSERT INTO peeper_likes (post_id, character_id) VALUES (?, ?)', [
      postId,
      characterId,
    ]);
    return true;
  } catch {
    // Duplicate key means it was already liked, which is the desired end state.
    return false;
  }
}

/**
 * Unlike a post.
 *
 * The single DELETE this surface has, and it is scoped to the caller's own like
 * by the `(post_id, character_id)` primary key. There is no way to express
 * "delete somebody else's like" through this call.
 */
export async function unlikePost(characterId: string, postId: string): Promise<boolean> {
  await query('DELETE FROM peeper_likes WHERE post_id = ? AND character_id = ?', [
    postId,
    characterId,
  ]);

  return true;
}

export type ReportReason = 'spam' | 'harassment' | 'impersonation' | 'other';

const REASONS: ReportReason[] = ['spam', 'harassment', 'impersonation', 'other'];

/**
 * Report a post. The website can file one but can never resolve one, because
 * resolution is an UPDATE (ADR-0019).
 */
export async function reportPost(
  reporterCharacterId: string,
  postId: string,
  reason: string,
): Promise<WriteResult> {
  if (!REASONS.includes(reason as ReportReason)) {
    return { ok: false, error: 'Unbekannter Grund.' };
  }

  const id = newUuid();

  try {
    await query(
      'INSERT INTO peeper_reports (id, reporter, post_id, reason) VALUES (?, ?, ?, ?)',
      [id, reporterCharacterId, postId, reason],
    );
  } catch {
    return { ok: false, error: 'Die Meldung konnte nicht übermittelt werden.' };
  }

  return { ok: true, id };
}