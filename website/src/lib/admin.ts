/**
 * Admin surface: the application queue and the decision.
 *
 * This module is the ONLY place that touches `adminDb()`. Everything it does is
 * an approval decision, so every entry point here is staff-gated at the page
 * level and re-checks inside the action.
 *
 * Note what changed relative to ADR-0007 (2026-10-11): approving used to be a
 * Discord staff-bot capability and impossible from the web by construction. The
 * owner chose a web admin area instead. The UPDATE is column-scoped in the
 * grant, so an admin can decide an application but cannot rewrite what the
 * applicant wrote or hand it to a different person.
 */
import 'server-only';

import { adminQuery, adminUpdateApplication } from './db';
import { requireStaff } from './auth';
import type { ApplicationStatus } from './applications';

export interface QueueEntry {
  id: string;
  discord_id: string;
  status: ApplicationStatus;
  submitted_at: string;
  reviewed_at: string | null;
}

export type AdminResult = { ok: true } | { ok: false; error: string };

const STATUSES: ApplicationStatus[] = ['submitted', 'under_review', 'approved', 'rejected'];

/**
 * The queue.
 *
 * Read on the ADMIN connection even though the public one could do it too. That
 * is not tidiness: it keeps a single place where applications are read as a
 * list, so if the grant is ever tightened, this view is already on the account
 * that would still have it.
 */
export async function queue(status?: ApplicationStatus, limit = 50): Promise<QueueEntry[]> {
  if (status && !STATUSES.includes(status)) return [];

  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 200);

  return adminQuery<QueueEntry>(
    `SELECT id, discord_id, status, submitted_at, reviewed_at
       FROM applications
      WHERE (? IS NULL OR status = ?)
      ORDER BY submitted_at ASC
      LIMIT ${safeLimit}`,
    [status ?? null, status ?? null],
  );
}

/** One application in full, for the review screen. */
export async function application(id: string) {
  if (!/^[0-9a-f-]{36}$/.test(id)) return null;

  const rows = await adminQuery(
    `SELECT id, discord_id, status, answers, submitted_at, reviewed_at, reviewed_by, decision_note
       FROM applications
      WHERE id = ?
      LIMIT 1`,
    [id],
  );

  return rows[0] ?? null;
}

/** How many applications sit in each state. Drives the queue tabs. */
export async function queueCounts(): Promise<Record<string, number>> {
  const rows = await adminQuery<{ status: string; c: number }>(
    `SELECT status, COUNT(*) AS c FROM applications GROUP BY status`,
  );

  const counts: Record<string, number> = {};
  for (const row of rows) counts[row.status] = Number(row.c);

  return counts;
}

/**
 * Approve or reject an application.
 *
 * `reviewed_by` is the CHARACTER id, not the Discord ID: the decision belongs to
 * a member of the team, and a staff flag on a character is what that means here.
 * It is resolved from the session, never accepted as an argument.
 */
export async function decide(
  id: string,
  status: ApplicationStatus,
  decisionNote: string | null,
): Promise<AdminResult> {
  const staff = await requireStaff();
  if (!staff) return { ok: false, error: 'Nicht autorisiert.' };

  if (!/^[0-9a-f-]{36}$/.test(id)) {
    return { ok: false, error: 'Unbekannte Bewerbung.' };
  }

  if (!STATUSES.includes(status)) {
    return { ok: false, error: 'Unbekannter Status.' };
  }

  const note = decisionNote?.trim() || null;
  if (note && note.length > 500) {
    return { ok: false, error: 'Die Notiz ist zu lang.' };
  }

  try {
    const { linkedCharacter } = await import('./identity');
    const link = await linkedCharacter(staff.discordId);

    if (!link) {
      return {
        ok: false,
        error: 'Dein Charakter ist nicht verknüpft, daher kann keine Entscheidung zugeordnet werden.',
      };
    }

    const affected = await adminUpdateApplication(id, {
      status,
      reviewed_at: new Date().toISOString().slice(0, 19).replace('T', ' '),
      reviewed_by: link.characterId,
      decision_note: note,
    });

    if (affected === 0) {
      return { ok: false, error: 'Keine Bewerbung mit dieser ID gefunden.' };
    }
  } catch (error) {
    if (error instanceof Error && error.message.includes('DB_ADMIN_USER')) {
      // Surfaced rather than swallowed: a missing admin credential looks exactly
      // like "approval silently does nothing", which is the failure worth never
      // having.
      return { ok: false, error: error.message };
    }
    return { ok: false, error: 'Die Entscheidung konnte nicht gespeichert werden.' };
  }

  return { ok: true };
}