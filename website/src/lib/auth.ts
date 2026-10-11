import { cookies } from 'next/headers';

import { decodeSession, type Session } from './session';

/**
 * The signed-in session, or null.
 *
 * This is the ONLY source of identity on this site. Server actions call it and
 * take `discordId` from the result; nothing accepts a Discord ID as input.
 */
export async function currentSession(): Promise<Session | null> {
  const store = await cookies();
  return decodeSession(store.get('nifty_session')?.value);
}

/** The signed-in session, or a thrown error. Use in any action that writes. */
export async function requireSession(): Promise<Session> {
  const session = await currentSession();
  if (!session) {
    throw new Error('Not signed in.');
  }
  return session;
}