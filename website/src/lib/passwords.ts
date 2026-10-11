/**
 * Password hashing.
 *
 * scrypt from node:crypto, no dependency. That is a deliberate trade: a package
 * like bcrypt or argon2 would be a better-reviewed implementation and a supply
 * chain to keep patched, bought with a function the runtime already ships. If
 * this ever stops being true the honest move is to swap the module, not to
 * reimplement crypto.
 *
 * Parameters live here and not in the database, because they are a property of
 * the code that CALLS the hash, not of the row. Changing them invalidates every
 * existing hash, so they are versioned below and the version is part of the
 * stored string.
 *
 * STORED FORMAT: scrypt$<N>$<r>$<p>$<saltHex>$<hashHex>
 *
 * The parameters are in the string so that raising the cost later does not lock
 * anyone out: an old hash is still verifiable with the parameters it was made
 * with, and `needsRehash` tells the caller to upgrade it on next sign-in.
 */
import { createHash, randomBytes, scrypt, timingSafeEqual } from 'node:crypto';

const SCRYPT_N = 16384;
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const SALT_BYTES = 16;
const KEY_BYTES = 32;

/** SHA-256 of a token, for the confirmation link. Tokens are high entropy, so a
 *  slow hash buys nothing here — this only stops a database read from handing
 *  over a working link. */
export function sha256(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

function derive(password: string, salt: Buffer, N: number, r: number, p: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scrypt(password, salt, KEY_BYTES, { N, r, p, maxmem: 64 * 1024 * 1024 }, (error, key) => {
      if (error) reject(error);
      else resolve(key);
    });
  });
}

/**
 * Hash a password for storage.
 *
 * The returned string is self-describing; nothing else needs to remember the
 * parameters.
 */
export async function hashPassword(password: string): Promise<{ hash: string; salt: string }> {
  const salt = randomBytes(SALT_BYTES);
  const key = await derive(password, salt, SCRYPT_N, SCRYPT_R, SCRYPT_P);

  return {
    hash: key.toString('hex'),
    salt: salt.toString('hex'),
  };
}

/**
 * Check a password against a stored hash.
 *
 * Always spends the same work, including when the user does not exist. That is
 * the second half of why the caller must not return early on "no such account":
 * the timing of "unknown email" versus "wrong password" is otherwise a free
 * oracle for which addresses are registered, which is a list worth having.
 * (The caller still returns the SAME message for both — see users.ts.)
 */
export async function verifyPassword(
  password: string,
  storedHash: string,
  saltHex: string,
): Promise<boolean> {
  const expected = Buffer.from(storedHash, 'hex');
  if (expected.length !== KEY_BYTES) return false;

  const actual = await derive(password, Buffer.from(saltHex, 'hex'), SCRYPT_N, SCRYPT_R, SCRYPT_P);

  // Lengths are equal by construction above; timingSafeEqual throws otherwise,
  // and the throw would itself be a distinguishable answer.
  return timingSafeEqual(expected, actual);
}

/**
 * A random, URL-safe token for the confirmation link.
 *
 * 32 bytes. Long enough that guessing is not a strategy, and short enough that
 * nobody copies it by hand.
 */
export function randomToken(): string {
  return randomBytes(32).toString('base64url');
}

/**
 * Minimum password rules.
 *
 * Length only, no composition rules. "At least ten characters" beats "one upper,
 * one lower, one digit, one symbol" in every published study of this: the
 * composition rules produce `Passw0rd!` and punish people who write sentences.
 */
export const PASSWORD_MIN = 10;

export function checkPasswordStrength(password: string): true | string {
  if (password.length < PASSWORD_MIN) {
    return `Das Passwort muss mindestens ${PASSWORD_MIN} Zeichen haben.`;
  }
  if (password.length > 200) {
    return 'Das Passwort ist zu lang.';
  }
  return true;
}

/**
 * Email shape check.
 *
 * Deliberately loose. A strict RFC validator rejects addresses that work, and
 * the only real test of an address is a message arriving at it — which is what
 * the confirmation link is for. This rejects the things that are certainly wrong
 * (no @, no dot in the domain, whitespace, absurd length).
 */
export function normalizeEmail(input: string): string | null {
  const email = input.trim().toLowerCase();
  if (email.length === 0 || email.length > 254) return null;
  if (/\s/.test(email)) return null;

  const at = email.lastIndexOf('@');
  if (at < 1 || at === email.length - 1) return null;

  const domain = email.slice(at + 1);
  if (!domain.includes('.') || domain.startsWith('.') || domain.endsWith('.')) return null;
  if (!/^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/.test(email)) return null;

  return email;
}

/**
 * Username shape check.
 *
 * A display name, not a login. Length and charset are the only rules: 3–32
 * characters, letters/digits/underscore/hyphen, must start and end with a
 * letter or digit. No uniqueness — two people can pick the same name; the
 * field is a label, not an identity.
 */
const USERNAME_PATTERN = /^[A-Za-z0-9](?:[A-Za-z0-9_-]{1,30}[A-Za-z0-9])?$/;

export function normalizeUsername(input: string): string | null {
  const username = input.trim();
  if (username.length < 3 || username.length > 32) return null;
  if (!USERNAME_PATTERN.test(username)) return null;
  return username;
}