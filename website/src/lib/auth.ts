import { cache } from 'react';
import { cookies } from 'next/headers';

import { decodeSession, SESSION_COOKIE, type Session } from './session';
import { findUser, linkedDiscord, type DiscordLink, type PortalUser } from './users';
import { isStaff } from './identity';

/**
 * Who is signed in: the ACCOUNT, plus whatever Discord it has attached.
 *
 * This module is the boundary between "what the cookie says" and "what the
 * database says", and the direction of that boundary is the whole design. The
 * cookie holds a user ID and an email; both are re-read from the database before
 * anything is rendered or written. `discord` in particular is NOT in the cookie at
 * all any more - it is looked up per request, which is what makes unlinking and
 * re-linking take effect immediately instead of at the next sign-in.
 *
 * Two extra facts are resolved here rather than by each caller, because both were
 * previously re-derived in three places and drifted:
 *
 *   `isStaff`  staff is a Discord ROLE, so it can only be answered for an account
 *              that has actually linked a Discord account.
 *   `verified` what the confirmation link did, read from the one column the
 *              website account cannot write.
 */
export interface Account {
  user: PortalUser;
  /** Null until the Discord round trip has been completed on /account. */
  discord: DiscordLink | null;
  /** Derived, never stored: staff is a Discord role, so no link means no staff. */
  isStaff: boolean;
}

/**
 * The signed-in account, or null.
 *
 * This is the ONLY source of identity on this site. Callers take `user.id` and
 * `discord.discordId` from the result; nothing accepts either as input.
 *
 * The session decodes first and the database second. A cookie whose account has
 * since been deleted therefore reads as signed out rather than as an account with
 * null fields, which is the state every caller already handles.
 *
 * Wrapped in `cache()` because the layout and the page both ask. One render that
 * touches /apply runs this twice — once for the navigation, once for the gate —
 * and without the memo that is three extra queries per page for every signed-in
 * visitor. The memo is per request and does nothing across requests, so it cannot
 * serve a stale account.
 */
export const currentAccount = cache(async (): Promise<Account | null> => {
  const store = await cookies();
  const session = decodeSession(store.get(SESSION_COOKIE)?.value);
  if (!session) return null;

  return resolveAccount(session);
});

/** The same, for code that already holds a decoded session. */
async function resolveAccount(session: Session): Promise<Account | null> {
  const user = await findUser(session.userId);
  if (!user) return null;

  const discord = await linkedDiscord(user.id);

  return {
    user,
    discord,
    // A staff check for an account with no Discord link would be a query for a
    // value that cannot exist, and `isStaff(null)` would be a lie told by a
    // string coercion.
    isStaff: discord ? await isStaff(discord.discordId) : false,
  };
}

/** The signed-in account, or a thrown error. Use in any action that writes. */
export async function requireAccount(): Promise<Account> {
  const account = await currentAccount();
  if (!account) {
    throw new Error('Not signed in.');
  }
  return account;
}

/**
 * The signed-in account, but only if it belongs to the moderation team.
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
export async function requireStaffAccount(): Promise<Account | null> {
  const account = await requireAccount();
  return account.isStaff ? account : null;
}