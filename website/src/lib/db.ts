/**
 * Database access.
 *
 * Deliberately minimal. There is no query builder and no ORM: the grant set in
 * `database/grants.sql` is the security model, so every statement below is one
 * someone can read next to the privilege it requires and check by hand.
 *
 * The pool runs as `nifty_website`. If that account ever lacks a privilege the
 * website needs, this file throws - it does not fall back to a more privileged
 * connection.
 */
import 'server-only';

import mysql from 'mysql2/promise';

import { config } from './config';

/**
 * Where the pools live between hot reloads.
 *
 * In `next dev` the module is re-evaluated on every file change, so a plain
 * `let pool = null` at module scope resets to null and `createPool` runs again
 * — leaving the previous pool with its connections still open. After a few
 * reloads the MySQL server hits `max_connections` and refuses every new
 * connection with "Too many connections". Stashing the pool on `globalThis`
 * makes the handle survive the reload; the underlying TCP connections stay
 * open for the lifetime of the dev process, which is what we want anyway.
 */
const globalForDb = globalThis as unknown as {
  __nifty_db_pool?: mysql.Pool;
  __nifty_db_admin_pool?: mysql.Pool;
};

/** The ordinary pool. Everything a visitor can reach runs on this. */
export function db(): mysql.Pool {
  if (globalForDb.__nifty_db_pool) return globalForDb.__nifty_db_pool;

  globalForDb.__nifty_db_pool = mysql.createPool({
    host: config.db.host,
    port: config.db.port,
    user: config.db.user,
    password: config.db.password,
    database: config.db.database,
    waitForConnections: true,
    connectionLimit: 5,

    // DECIMAL columns must arrive as strings. `supportBigNumbers` alone would
    // turn a balance into a float, and money is never a float (ADR-0005).
    decimalNumbers: false,
    dateStrings: true,

    // The application answers are JSON in a JSON column; mysql2 would hand back
    // a parsed object only if asked, and we want the raw string so that what we
    // stored is what we display.
    multipleStatements: false,
  });

  return globalForDb.__nifty_db_pool;
}

/**
 * The ADMIN pool. A second connection with separate credentials, used only by
 * the /admin routes.
 *
 * This exists so the separation is a property of the DATABASE, not of a comment
 * saying which module is careful. A bug in the public site runs on `db()` and
 * cannot reach an UPDATE privilege even if it wants to; reaching it requires
 * deliberately calling this function from a staff-gated route.
 *
 * It throws rather than falling back when the credentials are absent, because a
 * silent fallback would turn "the admin area is unreachable" into "the admin
 * area runs on the public account" — which is the exact failure the split
 * prevents.
 */
export function adminDb(): mysql.Pool {
  const user = process.env.DB_ADMIN_USER;
  const password = process.env.DB_ADMIN_PASSWORD;

  if (!user || !password) {
    throw new Error(
      'DB_ADMIN_USER / DB_ADMIN_PASSWORD are not set, so the admin area cannot ' +
        'open its own connection. It deliberately does not fall back to the ' +
        'public account: that account cannot UPDATE anything, and pretending ' +
        'otherwise would hide the misconfiguration until an approval silently ' +
        'stopped working.',
    );
  }

  if (globalForDb.__nifty_db_admin_pool) return globalForDb.__nifty_db_admin_pool;

  globalForDb.__nifty_db_admin_pool = mysql.createPool({
    host: config.db.host,
    port: config.db.port,
    user,
    password,
    database: config.db.database,
    waitForConnections: true,
    connectionLimit: 2,
    decimalNumbers: false,
    dateStrings: true,
    multipleStatements: false,
  });

  return globalForDb.__nifty_db_admin_pool;
}

/** Run a SELECT on the admin connection. */
export async function adminQuery<T = Record<string, unknown>>(
  sql: string,
  params: any[] = [],
): Promise<T[]> {
  const [rows] = await adminDb().execute(sql, params);
  return rows as T[];
}

/**
 * Run a COLUMN-SCOPED UPDATE on the admin connection.
 *
 * `columns` is a whitelist, not a convenience: the caller cannot pass a column
 * name derived from user input, and an accidental `SET answers = ?` cannot be
 * typed here at all. The grant enforces the same list; this makes the mistake
 * impossible before the database ever sees it.
 */
const ADMIN_WRITABLE_APPLICATION_COLUMNS = [
  'status',
  'reviewed_at',
  'reviewed_by_discord_id',
  'decision_note',
] as const;

export async function adminUpdateApplication(
  id: string,
  values: Partial<Record<(typeof ADMIN_WRITABLE_APPLICATION_COLUMNS)[number], unknown>>,
): Promise<number> {
  const sets: string[] = [];
  // `any[]`, not `unknown[]`: mysql2's execute() is typed against its own
  // `ExecuteValues` union, which `unknown[]` does not satisfy even though every
  // value pushed here is a plain string, null or number.
  const params: any[] = [];

  for (const column of ADMIN_WRITABLE_APPLICATION_COLUMNS) {
    if (values[column] === undefined) continue;
    sets.push(`${column} = ?`);
    params.push(values[column]);
  }

  if (sets.length === 0) return 0;

  params.push(id);
  const [result] = await adminDb().execute(
    `UPDATE applications SET ${sets.join(', ')} WHERE id = ?`,
    params,
  );

  return (result as mysql.ResultSetHeader).affectedRows;
}

/**
 * The soft-delete columns on `peeper_posts`.
 *
 * A whitelist for the same reason as the application one: the column names come
 * from here, never from a caller, so "edit the body of a post" is not a typo
 * away. `deleted_by` stays NULL on this surface — the team deletes by Discord ID
 * — and the game server keeps the character-keyed path.
 */
const ADMIN_WRITABLE_POST_COLUMNS = [
  'deleted_at',
  'deleted_by_discord_id',
  'deleted_reason',
] as const;

/**
 * Soft-delete one post, but only if it is not already deleted.
 *
 * The `deleted_at IS NULL` in the WHERE clause is load-bearing: without it a
 * second moderator clicking delete would overwrite the first one's reason and
 * timestamp, and the surviving record would be the LAST decision rather than the
 * first one. Zero affected rows means "already gone", which the caller reports
 * rather than silently overwriting.
 */
export async function adminSoftDeletePost(
  postId: string,
  values: Partial<Record<(typeof ADMIN_WRITABLE_POST_COLUMNS)[number], unknown>>,
): Promise<number> {
  const sets: string[] = [];
  const params: any[] = [];

  for (const column of ADMIN_WRITABLE_POST_COLUMNS) {
    if (values[column] === undefined) continue;
    sets.push(`${column} = ?`);
    params.push(values[column]);
  }

  if (sets.length === 0) return 0;

  params.push(postId);
  const [result] = await adminDb().execute(
    `UPDATE peeper_posts SET ${sets.join(', ')} WHERE id = ? AND deleted_at IS NULL`,
    params,
  );

  return (result as mysql.ResultSetHeader).affectedRows;
}

/** Run a SELECT and get rows back. */
export async function query<T = Record<string, unknown>>(
  sql: string,
  params: any[] = [],
): Promise<T[]> {
  const [rows] = await db().execute(sql, params);
  return rows as T[];
}

/** Run a SELECT expected to match at most one row. */
export async function one<T = Record<string, unknown>>(
  sql: string,
  params: any[] = [],
): Promise<T | null> {
  const rows = await query<T>(sql, params);
  return rows.length > 0 ? rows[0] : null;
}

/** Run an INSERT. Returns the new auto-increment id. */
export async function insert(sql: string, params: any[] = []): Promise<number> {
  const [result] = await db().execute(sql, params);
  return (result as mysql.ResultSetHeader).insertId;
}

/**
 * Run statements in one transaction.
 *
 * Used wherever a read has to be trusted to describe the same state the write
 * lands on - the Peeper author resolution is the case that matters (ADR-0022).
 */
export async function transaction<T>(
  work: (conn: mysql.PoolConnection) => Promise<T>,
): Promise<T> {
  const conn = await db().getConnection();
  try {
    await conn.beginTransaction();
    const result = await work(conn);
    await conn.commit();
    return result;
  } catch (error) {
    await conn.rollback();
    throw error;
  } finally {
    conn.release();
  }
}

/**
 * A v4 UUID, generated the same way the game server does.
 *
 * `crypto.randomUUID` is available in Node 19+ and we require Node 22, so there
 * is no reason to hand-roll this.
 */
export function newUuid(): string {
  return crypto.randomUUID();
}