'use server';

import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { createCharacter, existingCharacterForDiscord } from '@/lib/characters';

export type CharacterState = { error?: string } | undefined;

const GENDERS = new Set(['male', 'female', 'nonbinary']);

const ADULT_YEARS = 18;
const MIN_YEAR = 1900;

/**
 * Create the character for the currently signed-in account.
 *
 * Two gates before the procedure runs: the application must be approved (the
 * procedure itself will reject a character with no resolved account, but
 * "no account" is the wrong message for "you never applied"), and the
 * account must not already own a character (ADR-0008 — one character per
 * account). Both checks hit the database directly so a stale page does not
 * let a second character slip through.
 */
export async function createCharacterAction(
  _previous: CharacterState,
  form: FormData,
): Promise<CharacterState> {
  const account = await currentAccount();
  if (!account) redirect('/login');
  if (!account.discord) {
    return { error: 'Discord muss verknüpft sein, bevor ein Charakter angelegt werden kann.' };
  }
  if (!account.user.emailVerifiedAt) {
    return { error: 'Die E-Mail-Adresse muss bestätigt sein.' };
  }
  if (!account.isStaff && !await hasApprovedApplication(account.user.id)) {
    return { error: 'Die Bewerbung wurde noch nicht freigegeben.' };
  }

  // The two character gates: the same account cannot create twice, and the
  // form would not render in that case anyway. The check is here so a direct
  // POST cannot bypass the UI.
  const existing = await existingCharacterForDiscord(account.discord.discordId);
  if (existing) {
    redirect(`/apply/character/done`);
  }

  const firstName = String(form.get('first_name') ?? '').trim();
  const lastNameRaw = String(form.get('last_name') ?? '').trim();
  const gender = String(form.get('gender') ?? '');
  const dob = String(form.get('date_of_birth') ?? '');
  const birthplaceRaw = String(form.get('birthplace') ?? '').trim();

  if (firstName.length === 0 || firstName.length > 64) {
    return { error: 'Bitte einen Vornamen angeben (maximal 64 Zeichen).' };
  }
  if (lastNameRaw.length > 64) {
    return { error: 'Der Nachname ist zu lang (maximal 64 Zeichen).' };
  }
  if (!GENDERS.has(gender)) {
    return { error: 'Bitte ein Geschlecht angeben.' };
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dob)) {
    return { error: 'Bitte ein gültiges Geburtsdatum angeben.' };
  }
  const dobDate = new Date(dob);
  if (Number.isNaN(dobDate.getTime())) {
    return { error: 'Bitte ein gültiges Geburtsdatum angeben.' };
  }
  const now = new Date();
  const eighteenYearsAgo = new Date(
    now.getFullYear() - ADULT_YEARS,
    now.getMonth(),
    now.getDate(),
  );
  if (dobDate > eighteenYearsAgo) {
    return { error: 'Der Charakter muss am Tag der Registrierung volljährig sein.' };
  }
  if (dobDate.getFullYear() < MIN_YEAR) {
    return { error: 'Bitte ein realistisches Geburtsdatum angeben.' };
  }
  if (birthplaceRaw.length > 96) {
    return { error: 'Der Geburtsort ist zu lang (maximal 96 Zeichen).' };
  }

  const result = await createCharacter(account.discord.discordId, {
    firstName,
    lastName: lastNameRaw.length > 0 ? lastNameRaw : null,
    gender: gender as 'male' | 'female' | 'nonbinary',
    dateOfBirth: dob,
    birthplace: birthplaceRaw.length > 0 ? birthplaceRaw : null,
  });

  if (!result.ok) {
    return { error: result.message };
  }

  redirect('/apply/character/done');
}

async function hasApprovedApplication(userId: string): Promise<boolean> {
  const { one } = await import('@/lib/db');
  const row = await one<{ id: string }>(
    `SELECT id FROM applications WHERE user_id = ? AND status = 'approved' LIMIT 1`,
    [userId],
  );
  return row !== null;
}
