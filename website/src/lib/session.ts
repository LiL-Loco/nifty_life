/**
 * Signed-cookie sessions.
 *
 * The cookie carries the PORTAL USER ID and nothing else that matters. It is
 * signed with HMAC-SHA256, so the server can tell whether it was issued here -
 * which is what stops a visitor editing a cookie to become any account.
 *
 * It used to carry the Discord ID. That was correct while Discord WAS the login,
 * and it stopped being correct the moment registration moved to email + password
 * (migration 015): the Discord account became something an account ATTACHES, and
 * a session that hard-coded it meant a person could never change it, could not
 * have an account before applying, and could not be identified at all without
 * Discord. Everything Discord-shaped is now resolved per request through
 * `currentAccount()`.
 *
 * It is deliberately NOT an access token and grants nothing on its own. Every
 * privileged read re-derives from the database using the user ID in here, so a
 * stale cookie costs nothing but staleness.
 */
import 'server-only';

import { createHmac, timingSafeEqual } from 'node:crypto';

import { config } from './config';

/**
 * The one place the session cookie's name is written down.
 *
 * It used to be a literal at every read and every write, which meant a rename
 * was six edits with no compiler help — and a missed one silently logs nobody
 * out. The OAuth state cookie keeps its literal; it is set and cleared on
 * adjacent lines and is not read outside the two routes that write it.
 *
 * The `__Host-` prefix is load-bearing: it makes the cookie browser-side unforgeable.
 * Browsers refuse to accept a `__Host-` cookie that is missing `Secure`, has a
 * `Domain` attribute, or has a `Path` other than `/`. Without it, browsers in
 * certain configurations (third-party-cookie blocking, sandboxed iframes, some
 * privacy extensions) silently drop the cookie between the Set-Cookie on the
 * login response and the next same-origin GET, and the visitor gets logged out
 * between page loads. The prefix is the standard answer for this.
 */
export const SESSION_COOKIE = '__Host-nifty_session';
const MAX_AGE_SECONDS = 60 * 60 * 24 * 14; // 14 days

/** Any RFC-4122 UUID (v1/v3/v4/v5/v7). The version nibble is the first char of
 *  the third group and may be 1/3/4/5/7; the variant nibble is the first char
 *  of the fourth group and must be 8/9/a/b (RFC 4122). MariaDB's `UUID()`
 *  produces v1 (time-based), `crypto.randomUUID()` produces v4 — both must
 *  pass, otherwise signed cookies minted by one side silently fail on the other.
 */
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5-7][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export interface Session {
  /** `portal_users.id`. The only thing in here that grants anything. */
  userId: string;
  /** Kept so the header can say who you are without a query. NOT trusted:
   *  every read of the account re-derives from the database by `userId`. */
  email: string;
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

    // A v4 UUID, exactly what `newUuid()` produces. The check matters even
    // though the value is signed: it means a cookie minted by an older build
    // (which carried `discordId` and no `userId`) decodes to null instead of
    // producing an account with `userId: undefined` that every query then
    // stringifies into "WHERE id = undefined".
    if (typeof parsed.userId !== 'string' || !UUID_PATTERN.test(parsed.userId)) {
      return null;
    }
    if (typeof parsed.email !== 'string' || !parsed.email.includes('@')) {
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

/**
 * The public origin for redirects, given the inbound request.
 *
 * Behind nginx, `request.url` is `http://localhost:3000` — Next.js only sees the
 * hop it received, not the visitor's browser. Any `new URL('/x', request.url)`
 * therefore redirects the visitor to `localhost`, which their browser then
 * resolves to "this site" only when they're already on it (and otherwise
 * bounces them back to a host that serves nothing).
 *
 * Preference order matches the one in /api/login/route.ts:
 *   1. x-forwarded-host (nginx / Cloudflare / reverse proxies set this)
 *   2. origin header (the browser sends it on cross-origin POSTs; same-origin
 *      GETs include it too on modern browsers)
 *   3. NEXT_PUBLIC_BASE_URL / PUBLIC_URL env vars (operator-set fallback)
 *   4. request.url's origin — last resort, will be `http://localhost:3000`
 *      behind a reverse proxy, which is still better than throwing
 *
 * Returns just the origin (`https://colortastic.de`), without trailing slash,
 * so callers can compose `${origin}${path}` safely.
 */
export function publicOrigin(request: Request): string {
  const xfHost = request.headers.get('x-forwarded-host');
  const originHdr = request.headers.get('origin');
  const fromEnv = config.publicUrl;
  const fromXf = xfHost ? `https://${xfHost}` : null;
  const fromOrigin = originHdr ?? null;
  try {
    const fromNext = new URL(request.url).origin;
    // `http://localhost:3000` is the dev default; skip it so the env fallback wins.
    const looksLikeLoopback = fromNext.startsWith('http://localhost') || fromNext.startsWith('http://127.');
    const candidate = fromXf ?? fromOrigin ?? fromEnv ?? (looksLikeLoopback ? null : fromNext);
    if (candidate) return candidate.replace(/\/+$/, '');
  } catch {
    // fall through to env fallback
  }
  return fromEnv.replace(/\/+$/, '');
}