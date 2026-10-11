/**
 * The `staff` mirror.
 *
 * The bot is the ONLY writer of this table — `database/grants.sql` gives the two
 * website accounts SELECT and nothing else, so there is no second way for the
 * contents to change. That is deliberate: the reason for mirroring Discord roles
 * instead of asking Discord on every page load is that the website should never
 * hold the token that could change who is staff.
 */
import mysql from 'mysql2/promise';

import type { BotConfig } from './config.js';

export class StaffMirror {
  private readonly pool: mysql.Pool;
  private readonly roleIds: string[];

  constructor(config: BotConfig) {
    this.pool = mysql.createPool({
      ...config.db,
      connectionLimit: 2,
      waitForConnections: true,
    });
    this.roleIds = config.staffRoleIds;
  }

  /** Add or refresh one member. */
  async upsert(discordId: string, roleId: string): Promise<void> {
    await this.pool.execute(
      `INSERT INTO staff (discord_id, role_id)
            VALUES (?, ?)
       ON DUPLICATE KEY UPDATE role_id = VALUES(role_id), synced_at = NOW()`,
      [discordId, roleId],
    );
  }

  /**
   * Remove one member.
   *
   * DELETE, not a flag. A member who lost the staff role must actually lose
   * access; a `is_active` column that somebody has to remember to clear is a
   * way to keep a removed moderator in the admin area indefinitely.
   */
  async remove(discordId: string): Promise<void> {
    await this.pool.execute('DELETE FROM staff WHERE discord_id = ?', [discordId]);
  }

  /**
   * Replace the mirror from a full member list.
   *
   * One transaction, so /admin never sees a half-written state: the old rows and
   * the new rows become visible together or not at all. Without it there is a
   * window in which a genuine moderator looks like staff and another genuine
   * moderator does not, which is exactly the moment somebody gets locked out.
   *
   * Rows are removed by set difference rather than by `TRUNCATE`, so an
   * unexpected extra row in the table is left alone instead of being silently
   * destroyed by a routine resync.
   */
  async fullSync(entries: { discordId: string; roleId: string }[]): Promise<{ added: number; removed: number }> {
    const connection = await this.pool.getConnection();

    try {
      await connection.beginTransaction();

      for (const entry of entries) {
        await connection.execute(
          `INSERT INTO staff (discord_id, role_id)
                VALUES (?, ?)
           ON DUPLICATE KEY UPDATE role_id = VALUES(role_id), synced_at = NOW()`,
          [entry.discordId, entry.roleId],
        );
      }

      const found = entries.map((entry) => entry.discordId);

      let removed = 0;
      if (found.length === 0) {
        // Genuinely nobody holds a staff role any more. Say so loudly: this is
        // also what a misconfigured role ID looks like, and the difference
        // matters.
        const [result] = await connection.execute(
          'DELETE FROM staff WHERE role_id IN (?)',
          [this.roleIds],
        );
        removed = (result as mysql.ResultSetHeader).affectedRows;
      } else {
        const placeholders = found.map(() => '?').join(',');
        const [result] = await connection.execute(
          `DELETE FROM staff WHERE role_id IN (?) AND discord_id NOT IN (${placeholders})`,
          [this.roleIds, ...found],
        );
        removed = (result as mysql.ResultSetHeader).affectedRows;
      }

      await connection.commit();
      return { added: entries.length, removed };
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }
  }

  /** How many rows the mirror holds. Used only for the startup log line. */
  async count(): Promise<number> {
    const [rows] = await this.pool.execute('SELECT COUNT(*) AS c FROM staff');
    return Number((rows as { c: number }[])[0]?.c ?? 0);
  }

  async close(): Promise<void> {
    await this.pool.end();
  }
}