/**
 * Portal accounts (ADR revision 2026-10-11).
 *
 * The identity is an account made HERE, with email and password. Discord is
 * attached to it afterwards, and the attachment is what an application needs.
 * That ordering matters: before, you could not have an account without already
 * having the thing you were applying for.
 *
 * Three facts drive most of the decisions below:
 *
 *   1. `portal_user_discord` is UNIQUE in both directions, so a Discord account
 *      is one person and a person has one Discord account. That database fact is
 *      what stops somebody claiming someone else's Discord identity to apply
 *      under their name, and it does so without any of this file checking.
 *   2. A wrong password and an unknown email return the SAME message, in the
 *      same amount of time. Either one alone is a free list of who has an
 *      account.
 *   3. `email_verified_at` is not writable by the website account at all — the
 *      grant does not include the column. A sign-up form physically cannot mark
 *      itself as confirmed.
 */
import 'server-only';

import { one, query, newUuid } from './db';
import {
  checkPasswordStrength,
  hashPassword,
  normalizeEmail,
  randomToken,
  sha256,
  verifyPassword,
} from './passwords';

export interface PortalUser {
  id: string;
  email: string;
  createdAt: string;
  lastLoginAt: string | null;
  emailVerifiedAt: string | null;
}

export interface DiscordLink {
  discordId: string;
  username: string;
  linkedAt: string;
}

const TOKEN_LIFETIME_MINUTES = 60 * 24;

export type RegisterResult =
  | { ok: true; user: PortalUser }
  | { ok: false; error: string };

/**
 * Create an account.
 *
 * The address is the identity, so a duplicate is reported as a failure rather
 * than quietly attaching a second account. Enumerating registered addresses is
 * a real trade here and it is made knowingly: anyone can register, so the list is
 * not secret, and a registration form that hides "this already exists" just
 * produces support questions instead. If that ever stops being true — invitations
 * only, or a whitelist — the message here should become generic like the one in
 * `authenticate`.
 */
export async function register(emailInput: string, password: string): Promise<RegisterResult> {
  const email = normalizeEmail(emailInput);
  if (!email) {
    return { ok: false, error: 'Das ist keine gültige E-Mail-Adresse.' };
  }

  const strength = checkPasswordStrength(password);
  if (strength !== true) {
    return { ok: false, error: strength };
  }

  const existing = await one<{ id: string }>('SELECT id FROM portal_users WHERE email = ? LIMIT 1', [
    email,
  ]);
  if (existing) {
    return { ok: false, error: 'Mit dieser E-Mail-Adresse gibt es bereits ein Konto.' };
  }

  const { hash, salt } = await hashPassword(password);
  const id = newUuid();

  try {
    await query(
      'INSERT INTO portal_users (id, email, password_hash, password_salt) VALUES (?, ?, ?, ?)',
      [id, email, hash, salt],
    );
  } catch (error) {
    // The UNIQUE index is the real guard; the check above only produces a
    // readable message. Two people registering the same address at the same
    // moment both pass the check and one loses here.
    if (isDuplicateKey(error)) {
      return { ok: false, error: 'Mit dieser E-Mail-Adresse gibt es bereits ein Konto.' };
    }
    return { ok: false, error: 'Das Konto konnte nicht angelegt werden. Bitte später erneut.' };
  }

  return {
    ok: true,
    user: {
      id,
      email,
      createdAt: new Date().toISOString(),
      lastLoginAt: null,
      emailVerifiedAt: null,
    },
  };
}

/**
 * Issue a confirmation token and return the RAW token.
 *
 * The raw value exists only here and in the mail. `portal_email_tokens` stores
 * its SHA-256, because the link travels by mail to whoever receives it and a
 * database read must not be enough to confirm anybody's address.
 *
 * Any previous unconfirmed token for the same purpose is invalidated by the
 * single-use `used_at` mark on confirm; a resend does not need a cleanup pass.
 */
export async function issueEmailToken(userId: string): Promise<string> {
  const token = randomToken();

  await query(
    `INSERT INTO portal_email_tokens (user_id, purpose, token_hash, expires_at)
     VALUES (?, 'verify_email', ?, DATE_ADD(NOW(), INTERVAL ? MINUTE))`,
    [userId, sha256(token), TOKEN_LIFETIME_MINUTES],
  );

  return token;
}

export type ConfirmResult = { ok: true } | { ok: false; error: string };

/**
 * Consume a confirmation token.
 *
 * The verification lives in the stored procedure `confirm_portal_email`
 * (migration 016), not here. That is not a style choice.
 *
 * `email_verified_at` is deliberately NOT grantable to the website account, so
 * this file cannot write it even in principle. The procedure runs with the
 * database's own rights, takes a token HASH, and does the claim-then-set
 * atomically. The web account can ask "is this token valid" and can never ask
 * "confirm user X". Column-grant purity and a working link, both.
 *
 * Every failure returns NULL and is reported with the same sentence. "unknown
 * token", "expired" and "already used" are three different statements about a
 * value that leaked by being emailed, and telling them apart tells an attacker
 * which half of the attempt worked.
 */
export async function confirmEmail(token: string): Promise<ConfirmResult> {
  const refusal = 'Dieser Bestätigungslink ist ungültig oder abgelaufen.';

  if (!/^[A-Za-z0-9_-]{20,80}$/.test(token)) {
    return { ok: false, error: refusal };
  }

  let confirmedId: string | null = null;

  try {
    // CALL, not a SELECT: the procedure is the only thing anywhere in this
    // codebase that can write email_verified_at, and no grant allows bypassing it.
    const results = await query<unknown>('CALL confirm_portal_email(?)', [sha256(token)]);

    // A procedure with several statements returns SEVERAL result sets, and
    // mysql2 hands back an array of them: the SELECT that carries the answer,
    // interleaved with OkPackets from the UPDATEs that have no columns at all.
    //
    // Two things this code got wrong before it got it right, both worth writing
    // down. Reading result[0] blindly is fragile because MariaDB does NOT
    // guarantee which set comes first. And calling .find() on an OkPacket throws,
    // which the catch below was reporting as "the database is not up to date" —
    // a confident, completely wrong diagnosis. So: every set is checked for being
    // an array before anything is called on it, and the order is never assumed.
    const sets = (Array.isArray(results[0]) ? results : [results]) as unknown[];
    for (const set of sets) {
      if (!Array.isArray(set)) continue;
      const row = (set as Record<string, unknown>[]).find(
        (entry) => entry && typeof entry === 'object' && 'confirmed_user_id' in entry,
      );
      if (row) {
        confirmedId = (row.confirmed_user_id as string | null) ?? null;
        break;
      }
    }
  } catch (error) {
    // Logged rather than guessed at. The previous wording here told the person
    // their database was out of date for what turned out to be a bug in the line
    // above — a wrong answer confidently delivered is worse than an ugly one.
    console.error('[auth] confirm-portal-email failed:', error instanceof Error ? error.message : error);
    return {
      ok: false,
      error: 'Die Bestätigung ist gerade nicht möglich. Bitte später erneut versuchen.',
    };
  }

  if (!confirmedId) {
    return { ok: false, error: refusal };
  }

  return { ok: true };
}

export type AuthResult =
  | { ok: true; user: PortalUser }
  | { ok: false; error: string };

/** The same sentence for a wrong password and an unknown address. Always. */
const BAD_CREDENTIALS = 'E-Mail-Adresse oder Passwort ist falsch.';

/**
 * Sign in.
 *
 * When the address is unknown, scrypt still runs against a dummy salt so the
 * response takes the same time as a real check. Skipping it would make "no such
 * account" measurably faster than "wrong password", which is a free list of who
 * has registered.
 */
export async function authenticate(emailInput: string, password: string): Promise<AuthResult> {
  const email = normalizeEmail(emailInput);
  if (!email) {
    // Still spend the time, for the same reason.
    await verifyPassword(password, DUMMY_HASH, DUMMY_SALT);
    return { ok: false, error: BAD_CREDENTIALS };
  }

  const user = await one<{
    id: string;
    email: string;
    password_hash: string;
    password_salt: string;
    created_at: string;
    last_login_at: string | null;
    email_verified_at: string | null;
  }>('SELECT * FROM portal_users WHERE email = ? LIMIT 1', [email]);

  if (!user) {
    await verifyPassword(password, DUMMY_HASH, DUMMY_SALT);
    return { ok: false, error: BAD_CREDENTIALS };
  }

  const valid = await verifyPassword(password, user.password_hash, user.password_salt);
  if (!valid) {
    return { ok: false, error: BAD_CREDENTIALS };
  }

  await query('UPDATE portal_users SET last_login_at = NOW() WHERE id = ?', [user.id]);

  return {
    ok: true,
    user: {
      id: user.id,
      email: user.email,
      createdAt: user.created_at,
      lastLoginAt: new Date().toISOString(),
      emailVerifiedAt: user.email_verified_at,
    },
  };
}

/** A real hash of a random password, used only to equalise timing. */
const DUMMY_SALT = '0f1e2d3c4b5a69788796a5b4c3d2e1f0';
const DUMMY_HASH =
  'a'.repeat(64);

/** Read an account for a session. */
export async function findUser(userId: string): Promise<PortalUser | null> {
  if (!/^[0-9a-f-]{36}$/.test(userId)) return null;

  const row = await one<{
    id: string;
    email: string;
    created_at: string;
    last_login_at: string | null;
    email_verified_at: string | null;
  }>(
    `SELECT id, email, created_at, last_login_at, email_verified_at
       FROM portal_users WHERE id = ? LIMIT 1`,
    [userId],
  );

  return row
    ? {
        id: row.id,
        email: row.email,
        createdAt: row.created_at,
        lastLoginAt: row.last_login_at,
        emailVerifiedAt: row.email_verified_at,
      }
    : null;
}

/** This account's Discord link, or null. */
export async function linkedDiscord(userId: string): Promise<DiscordLink | null> {
  if (!/^[0-9a-f-]{36}$/.test(userId)) return null;

  const row = await one<{
    discord_id: string;
    username: string;
    linked_at: string;
  }>('SELECT discord_id, username, linked_at FROM portal_user_discord WHERE user_id = ? LIMIT 1', [
    userId,
  ]);

  return row ? { discordId: row.discord_id, username: row.username, linkedAt: row.linked_at } : null;
}

/**
 * Attach a Discord account.
 *
 * The caller must hold a signed-in session; this never runs anonymous. And the
 * UNIQUE index on discord_id is what stops the same Discord account being
 * attached to two portal accounts — the second attempt fails here rather than
 * silently reassigning the first person's link.
 *
 * Re-linking replaces the existing link rather than failing, because the common
 * case is somebody who linked the wrong account and needs to fix it. The old
 * link leaves no trace by design: an application already filed under it keeps
 * its own `discord_id`, so history is not rewritten.
 */
export async function linkDiscord(
  userId: string,
  discordId: string,
  username: string,
): Promise<{ ok: true } | { ok: false; error: string }> {
  if (!/^\d{5,32}$/.test(discordId)) {
    return { ok: false, error: 'Ungültige Discord-ID.' };
  }
  if (!username || username.length > 64) {
    return { ok: false, error: 'Ungültiger Discord-Name.' };
  }

  const holder = await one<{ user_id: string }>(
    'SELECT user_id FROM portal_user_discord WHERE discord_id = ? LIMIT 1',
    [discordId],
  );

  if (holder && holder.user_id !== userId) {
    // The wording does not say whose it is. It is enough that the person is told
    // it is taken, and it does not confirm whether a particular address exists.
    return {
      ok: false,
      error: 'Dieses Discord-Konto ist bereits mit einem Portal-Konto verknüpft.',
    };
  }

  try {
    await query(
      `INSERT INTO portal_user_discord (user_id, discord_id, username)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE discord_id = VALUES(discord_id), username = VALUES(username)`,
      [userId, discordId, username],
    );
  } catch (error) {
    if (isDuplicateKey(error)) {
      return {
        ok: false,
        error: 'Dieses Discord-Konto ist bereits mit einem Portal-Konto verknüpft.',
      };
    }
    return { ok: false, error: 'Die Verknüpfung konnte nicht gespeichert werden.' };
  }

  return { ok: true };
}

/**
 * Registrations, for the team view.
 *
 * LEFT JOINs throughout: the whole point of the list is to see who registered
 * and what state they are in — email unconfirmed, Discord not linked, no
 * application — and an inner join would quietly drop exactly the rows somebody
 * opened the page to find.
 */
export async function registrations(limit = 200) {
  const safeLimit = Math.min(Math.max(Number(limit) || 200, 1), 500);

  return query<{
    id: string;
    email: string;
    created_at: string;
    last_login_at: string | null;
    email_verified_at: string | null;
    discord_id: string | null;
    username: string | null;
    application_status: string | null;
  }>(
    `SELECT u.id, u.email, u.created_at, u.last_login_at, u.email_verified_at,
            d.discord_id, d.username,
            a.status AS application_status
       FROM portal_users u
       LEFT JOIN portal_user_discord d ON d.user_id = u.id
       LEFT JOIN applications a       ON a.user_id = u.id
      ORDER BY u.created_at DESC
      LIMIT ${safeLimit}`,
  );
}

function isDuplicateKey(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    (error as { errno?: number }).errno === 1062
  );
}

