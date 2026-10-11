/**
 * Signed-cookie sessions.
 *
 * The cookie carries the Discord ID and nothing else that matters. It is signed
 * with HMAC-SHA256, so the server can tell whether it was issued here — which is
 * what stops a visitor editing a cookie to become any Discord account, including
 * an approved one.
 *
 * It is deliberately NOT an access token and grants nothing on its own. Every
 * privileged read re-derives from the database using the Discord ID in here, so a
 * stale cookie costs nothing but staleness.
 */
import 'server-only';

import { createHmac, timingSafeEqual } from 'node:crypto';

import { config } from './config';

const COOKIE_NAME = 'nifty_session';
const MAX_AGE_SECONDS = 60 * 60 * 24 * 14; // 14 days

export interface Session {
  discordId: string;
  username: string;
  avatar: string | null;
  expiresAt: number;
}

function sign(payload: string): string {
  return createHmac('sha256', config.sessionSecret).update(payload).digest('base64url');
}

/** Encode a session into the value that goes into the cookie. */
export function encodeSession(session: Omit<Session, 'expiresAt'>): string {
  const payload = Buffer.from(
    JSON.stringify({ ...session, expiresAt: Date.now() + MAX_AGE_SECONDS * 1000 }),
  ).toString('base64url');

  return `${payload}.${sign(payload)}`;
}

/**
 * Decode and verify a cookie value.
 *
 * Returns null for anything we did not issue, including a well-formed cookie
 * whose signature does not match. The signature comparison is constant-time so
 * that a wrong signature cannot be discovered a character at a time.
 */
export function decodeSession(value: string | undefined): Session | null {
  if (!value) return null;

  const dot = value.lastIndexOf('.');
  if (dot <= 0) return null;

  const payload = value.slice(0, dot);
  const signature = value.slice(dot + 1);

  const expected = sign(payload);
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);

  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;

  try {
    const parsed = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as Session;

    if (typeof parsed.discordId !== 'string' || !/^\d{5,32}$/.test(parsed.discordId)) {
      return null;
    }
    if (typeof parsed.expiresAt !== 'number' || parsed.expiresAt < Date.now()) {
      return null;
    }

    return parsed;
  } catch {
    return null;
  }
}

export const sessionCookie = {
  name: COOKIE_NAME,
  maxAge: MAX_AGE_SECONDS,
};

/** Cookie attributes. httpOnly keeps it away from scripts, and `lax` still lets a Discord redirect carry it back in. */
export function cookieOptions() {
  return {
    httpOnly: true,
    sameSite: 'lax' as const,
    secure: config.isProduction,
    path: '/',
    maxAge: MAX_AGE_SECONDS,
  };
}