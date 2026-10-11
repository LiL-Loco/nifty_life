/**
 * Character creation (ADR-0008, migration 021).
 *
 * The website is the only path that creates characters, and it is the only
 * path that CAN create them: the `nifty_website` grant set has EXECUTE on
 * `create_character_from_web` and nothing else on `characters`. Every other
 * write is a column-scoped update, every other read is a SELECT.
 *
 * The procedure does the work that used to live in `identity.lua`: resolve
 * the account from the Discord ID, refuse duplicates, allocate a permanent
 * phone number, and write the character + wallet in one transaction. The
 * website only carries the inputs — first name, last name, gender, date of
 * birth, birthplace — and renders the result.
 */
import 'server-only';

import { one, query } from './db';

export interface CharacterInput {
  firstName: string;
  lastName: string | null;
  gender: 'male' | 'female' | 'nonbinary';
  dateOfBirth: string; // YYYY-MM-DD
  birthplace: string | null;
}

export type CreateCharacterResult =
  | { ok: true; characterId: string }
  | { ok: false; code: CreateCharacterError; message: string };

export type CreateCharacterError =
  | 'invalid_first_name'
  | 'invalid_last_name'
  | 'invalid_gender'
  | 'invalid_date_of_birth'
  | 'no_account'
  | 'already_has_character'
  | 'name_taken'
  | 'no_number_available'
  | 'error';

/**
 * Create a character for the given Discord ID.
 *
 * Calls the stored procedure. The procedure does the validation (first name
 * required, gender in the enum, age check), the uniqueness check, the phone
 * allocation, and the writes — so this function only needs to forward the
 * inputs and turn the procedure's result set into a discriminated union.
 *
 * Validation here is intentionally a thin pass: the procedure is the
 * authority, and re-validating in TypeScript would be a second place to keep
 * in sync. The form layer is where shape errors get a readable sentence.
 */
export async function createCharacter(
  discordId: string,
  input: CharacterInput,
): Promise<CreateCharacterResult> {
  const results = await query<{
    ok: number;
    character_id: string | null;
    code: string;
    message: string;
  }>('CALL create_character_from_web(?, ?, ?, ?, ?, ?)', [
    discordId,
    input.firstName,
    input.lastName,
    input.gender,
    input.dateOfBirth,
    input.birthplace,
  ]);

  // A procedure with several statements returns SEVERAL result sets, and
  // mysql2 hands back an array of them. The procedure's result set is the
  // last one with columns; OkPackets from the writes have no columns.
  const sets = (Array.isArray(results[0]) ? results : [results]) as unknown[];
  for (const set of sets) {
    if (!Array.isArray(set)) continue;
    const row = (set as Record<string, unknown>[]).find(
      (entry) => entry && typeof entry === 'object' && 'ok' in entry,
    );
    if (row) {
      const ok = Number(row.ok) === 1;
      const code = String(row.code ?? '');
      const message = String(row.message ?? '');
      const characterId = row.character_id ? String(row.character_id) : '';
      if (ok && characterId) {
        return { ok: true, characterId };
      }
      return {
        ok: false,
        code: isCreateCharacterError(code) ? code : 'error',
        message,
      };
    }
  }

  return { ok: false, code: 'error', message: 'Der Charakter konnte nicht angelegt werden.' };
}

function isCreateCharacterError(code: string): code is CreateCharacterError {
  return (
    code === 'invalid_first_name' ||
    code === 'invalid_last_name' ||
    code === 'invalid_gender' ||
    code === 'invalid_date_of_birth' ||
    code === 'no_account' ||
    code === 'already_has_character' ||
    code === 'name_taken' ||
    code === 'no_number_available'
  );
}

/**
 * The character this Discord ID already has, if any.
 *
 * Used to gate the creation form: the procedure refuses a second character
 * on the same account (ADR-0008), and the UI should refuse to show a form
 * that will only fail at the server.
 */
export async function existingCharacterForDiscord(
  discordId: string,
): Promise<{
  characterId: string;
  firstName: string;
  lastName: string | null;
  gender: 'male' | 'female' | 'nonbinary';
  dateOfBirth: string;
  birthplace: string | null;
  createdAt: string;
} | null> {
  const row = await one<{
    id: string;
    first_name: string;
    last_name: string | null;
    gender: 'male' | 'female' | 'nonbinary';
    date_of_birth: string;
    birthplace: string | null;
    created_at: string;
  }>(
    `SELECT id, first_name, last_name, gender, date_of_birth, birthplace, created_at
       FROM characters
      WHERE account_id = (SELECT id FROM accounts WHERE discord_id = ? LIMIT 1)
      LIMIT 1`,
    [discordId],
  );
  return row
    ? {
        characterId: row.id,
        firstName: row.first_name,
        lastName: row.last_name,
        gender: row.gender,
        dateOfBirth: String(row.date_of_birth).slice(0, 10),
        birthplace: row.birthplace,
        createdAt: String(row.created_at),
      }
    : null;
}
