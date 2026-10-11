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

let pool: mysql.Pool | null = null;

export function db(): mysql.Pool {
  if (pool) return pool;

  pool = mysql.createPool({
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

  return pool;
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