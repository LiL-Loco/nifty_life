/**
 * Applications (ADR-0007).
 *
 * The website submits; a human approves. That boundary is not implemented here -
 * it is implemented in `database/grants.sql`, where `nifty_website` receives
 * `SELECT, INSERT` on `applications` and nothing else. Approving is an UPDATE,
 * and this account physically cannot perform one.
 *
 * Everything below therefore follows from one rule: read what is yours, insert
 * what is yours, and never attempt a write that would change an existing row.
 */
import 'server-only';

import { insert, one, query, newUuid } from './db';
import { RULEBOOK_QUESTIONS, RULEBOOK_REFERENCE_TEXT } from './rulebook';
import { checkForCopying, copyWarningMessage } from './copycheck';

export type ApplicationStatus = 'submitted' | 'under_review' | 'approved' | 'rejected';

/** Bumped whenever the rulebook text changes, so an acknowledgement can be dated. */
export const RULEBOOK_VERSION = '2026-10-11';

export interface StoredAnswer {
  /** Stable id from RULEBOOK_QUESTIONS. */
  id: string;
  /** The question AS ASKED, stored alongside the answer.
   *
   *  Same reasoning as `author_name` on a Peeper post (ADR-0022): if the
   *  rulebook is reworded next year, an application from this year must still
   *  show the question the applicant actually answered. Without the snapshot the
   *  answers become unreadable. */
  question: string;
  answer: string;
}

export interface ApplicationAnswers {
  /**
   * That the rulebook was read.
   *
   * `at` and `version` are stamped by the SERVER when the row is written, never
   * by the client. A ticked box proves only that someone ticked a box; what a
   * reviewer needs is "when did they say they had read this, and which version".
   */
  rulebook: {
    read: boolean;
    at: string;
    version: string;
  };

  /** Exactly the questions in RULEBOOK_QUESTIONS, in order. */
  answers: StoredAnswer[];
}

export interface Application {
  id: string;
  discord_id: string;
  status: ApplicationStatus;
  answers: string;
  submitted_at: string;
  reviewed_at: string | null;
  decision_note: string | null;
}

export type SubmitResult = { ok: true; id: string } | { ok: false; error: string };

const LIMITS = {
  /** Shortest answer that is not a single word. A permanent-ban rule answered in
   *  four words is not an answer, it is a reflex — the point of the questions is
   *  to make the applicant think, so a floor is part of the rule. */
  answerMin: 25,
  answerMax: 2000,
} as const;

/**
 * Control characters and DEL.
 *
 * Written as escapes, not as literal bytes. An earlier version embedded the raw
 * characters, which put a NUL byte into the source file - the file still parsed,
 * but it counted as binary to every tool that touched it and a single stray
 * byte can end a command line.
 */
const CONTROL_CHARS = /[\x00-\x1F\x7F]/;

function clean(value: FormDataEntryValue | null, max: number): string | null {
  if (typeof value !== 'string') return null;

  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > max) return null;

  // Control characters have no place in a text field a human will read in
  // Discord, and they are how log lines and embeds get mangled.
  if (CONTROL_CHARS.test(trimmed)) return null;

  return trimmed;
}

/**
 * Validate the submitted answers.
 *
 * This runs on the server against a FormData the client controls entirely, so
 * every rule here is the real rule - the client-side step wizard is a
 * convenience, never the check.
 *
 * The twenty questions are asked once, in free text. There is no age, no
 * timezone, no experience field and no motivation field: nothing is asked that
 * the rulebook does not answer, and every question is answerable only from the
 * rulebook. That is the whole selection test - if the applicant could answer it
 * without opening the document, it is not a rulebook question.
 *
 * EMPTY ANSWERS. `validateAnswers` requires all twenty. The wizard lets an empty
 * box be stepped over, because a twenty-screen form that traps you on screen
 * nine is a form people abandon - but the form as a whole cannot be submitted
 * until every question has an answer. Navigation is forgiving, submission is not.
 */
export function validateAnswers(form: FormData): ApplicationAnswers | string {
  // The "I have read it" box. It is kept as a separate tick rather than implied
  // by the twenty answers: it is the one thing that is a declaration rather than
  // a demonstration.
  if (form.get('rulebook_read') !== 'on') {
    return 'Du musst bestätigen, dass du das Regelwerk gelesen hast.';
  }

  const answers: StoredAnswer[] = [];
  const missing: number[] = [];

  for (const item of RULEBOOK_QUESTIONS) {
    const index = answers.length + 1;
    const answer = clean(form.get(`answer_${item.id}`), LIMITS.answerMax);

    if (!answer) {
      // Collect them all rather than stopping at the first: being told "Frage 3
      // fehlt" twenty times in a row is the kind of friction that makes somebody
      // give up on the form entirely.
      missing.push(index);
      answers.push({ id: item.id, question: `${item.ref} ${item.question}`, answer: '' });
      continue;
    }

    if (answer.length < LIMITS.answerMin) {
      return `Bitte antworte auf Frage ${index} ausführlicher. Ein Satz in eigenen Worten reicht.`;
    }

    answers.push({
      id: item.id,
      // The question as asked TODAY is stored with the answer, so a reworded
      // question next year cannot orphan this application's answers.
      question: `${item.ref} ${item.question}`,
      answer,
    });
  }

  if (missing.length > 0) {
    return `Es fehlen noch ${missing.length} Antwort${missing.length === 1 ? '' : 'en'}: Frage ${missing.join(', ')}.`;
  }

  // --- Own words, or a copy -----------------------------------------------
  // Warned about, not refused. Refusing outright would be wrong for the honest
  // applicant who happens to quote a rule to make a point; and warning without
  // any way past it would just be a refusal with worse manners. So the first
  // submission is held, told what was observed, and the second is accepted once
  // they say they stand behind it — a moderator reads the answers and decides.
  const copyResult = checkForCopying({
    answers: answers.map((entry) => ({
      id: entry.id,
      question: entry.question,
      answer: entry.answer,
    })),
    rulebookReferenceText: RULEBOOK_REFERENCE_TEXT,
  });

  if (copyResult.suspicious && form.get('own_words_ack') !== 'on') {
    return copyWarningMessage(copyResult, RULEBOOK_QUESTIONS.map((q) => q.id));
  }

  return {
    rulebook: {
      read: true,
      // Stamped here, not taken from the request.
      at: new Date().toISOString(),
      version: RULEBOOK_VERSION,
    },
    answers,
  };
}

/**
 * Submit an application.
 *
 * `discordId` comes from the signed session and from nowhere else. A form field
 * named `discord_id` would be ignored even if it were present.
 *
 * One application per person, ever. The rule is a UNIQUE index
 * (`uq_applications_discord`, migration 010), so the check below is a courtesy
 * that produces a readable message and the duplicate-key catch is what actually
 * enforces it. Both exist because the pre-check loses races — two tabs, a double
 * click, a client retry — and the constraint does not.
 */
export async function submitApplication(
  discordId: string,
  answers: ApplicationAnswers,
): Promise<SubmitResult> {
  if (!/^\d{5,32}$/.test(discordId)) {
    return { ok: false, error: 'Deine Sitzung ist ungültig. Bitte melde dich erneut an.' };
  }

  const existing = await one<{ id: string; status: ApplicationStatus }>(
    'SELECT id, status FROM applications WHERE discord_id = ? LIMIT 1',
    [discordId],
  );

  if (existing) {
    return {
      ok: false,
      error: ALREADY_APPLIED_MESSAGE(existing.status),
    };
  }

  const id = newUuid();

  try {
    await insert('INSERT INTO applications (id, discord_id, answers) VALUES (?, ?, ?)', [
      id,
      discordId,
      JSON.stringify(answers),
    ]);
  } catch (error) {
    // ER_DUP_ENTRY. Somebody got in between the check above and this INSERT —
    // two tabs, or a retry. The unique index caught it, and the applicant is
    // told the same thing either way.
    if (isDuplicateKey(error)) {
      const current = await one<{ status: ApplicationStatus }>(
        'SELECT status FROM applications WHERE discord_id = ? LIMIT 1',
        [discordId],
      );
      return {
        ok: false,
        error: ALREADY_APPLIED_MESSAGE(current?.status ?? 'submitted'),
      };
    }

    // Never surface the driver's message: it would name tables and columns to a
    // stranger, and a failed insert is an operational problem, not theirs.
    return {
      ok: false,
      error:
        'Die Bewerbung konnte gerade nicht gespeichert werden. Bitte versuch es noch einmal.',
    };
  }

  return { ok: true, id };
}

/**
 * The refusal, worded for the state they are actually in.
 *
 * "You already applied" is not the same message for someone whose application is
 * sitting unread and for someone who was rejected — the second needs to know that
 * the door is a conversation, not a second form.
 */
function ALREADY_APPLIED_MESSAGE(status: ApplicationStatus): string {
  if (status === 'rejected') {
    return 'Du hast bereits beworben, und deine Bewerbung wurde abgelehnt. Eine zweite Bewerbung ist nicht möglich — schreib dich dazu direkt im Discord.';
  }

  if (status === 'approved') {
    return 'Du bist bereits freigegeben. Eine erneute Bewerbung ist nicht möglich.';
  }

  return 'Du hast bereits eine Bewerbung eingereicht. Sie wird von einem Menschen gelesen — schau unter "Status" nach.';
}

/** MariaDB and MySQL both report a unique violation as 1062. */
function isDuplicateKey(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    (error as { errno?: number }).errno === 1062
  );
}

/**
 * This account's application.
 *
 * There is only ever one (`uq_applications_discord`, migration 010), so this is
 * the application rather than the latest of several. The ORDER BY is kept as
 * documentation rather than as logic: if the unique index were ever dropped,
 * the page would silently start showing a different row.
 */
export async function latestApplication(
  discordId: string,
): Promise<Application | null> {
  return one<Application>(
    `SELECT id, discord_id, status, answers, submitted_at, reviewed_at, decision_note
       FROM applications
      WHERE discord_id = ?
      ORDER BY submitted_at DESC, id DESC
      LIMIT 1`,
    [discordId],
  );
}

export async function applicationHistory(discordId: string, limit = 5) {
  return query<Application>(
    `SELECT id, status, submitted_at, reviewed_at, decision_note
       FROM applications
      WHERE discord_id = ?
      ORDER BY submitted_at DESC, id DESC
      LIMIT ${Number(limit)}`,
    [discordId],
  );
}

/**
 * Whether an active ban exists for this Discord ID.
 *
 * The website has SELECT on `bans` precisely so the status page can say "you are
 * banned" instead of letting someone discover it by being kicked.
 */
export async function activeBan(
  discordId: string,
): Promise<{ reason: string | null; expires_at: string | null } | null> {
  const row = await one<{ reason: string | null; expires_at: string | null }>(
    `SELECT reason, expires_at
       FROM bans
      WHERE discord_id = ?
        AND revoked_at IS NULL
        AND (expires_at IS NULL OR expires_at > NOW())
      LIMIT 1`,
    [discordId],
  );

  return row;
}