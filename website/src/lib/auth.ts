import { cookies } from 'next/headers';

import { decodeSession, type Session } from './session';
import { isStaff } from './identity';

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

/**
 * The signed-in session, but only if it belongs to the moderation team.
 *
 * Returns null for "signed in, not staff" so a page can render a refusal
 * instead of an error page. A missing session still throws: that one is a bug
 * in the caller rather than a state a user can be in.
 *
 * Note what this does NOT do — it does not open the admin connection. Deciding
 * whether to trust the privileged connection cannot itself depend on the
 * privileged connection, so the check runs on the public pool and only the
 * route that already passed it may call `adminDb()`.
 */
export async function requireStaff(): Promise<Session | null> {
  const session = await requireSession();
  return (await isStaff(session.discordId)) ? session : null;
}