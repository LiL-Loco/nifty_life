'use server';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';

import { encodeSession, cookieOptions } from '@/lib/session';
import { authenticate, issueEmailToken, register } from '@/lib/users';
import { sendMail, mailConfigured, publicUrl } from '@/lib/mailer';

export type AuthState = { error?: string; ok?: string } | undefined;

/**
 * Create an account, then send the confirmation link.
 *
 * The order is deliberate and the second step is NOT conditional: an account with
 * an unconfirmed address is a real account, it simply cannot apply yet. Silently
 * skipping the mail would leave somebody who typed their address correctly staring
 * at a form that refuses to continue for no stated reason, which is a worse
 * failure than an account that exists and is visibly waiting for a link.
 *
 * What the person is told afterwards does not depend on whether the mail went out
 * — it is the same sentence either way, naming what to do next.
 */

const MAIL_SUBJECT = 'Bestätige deine E-Mail-Adresse — Nifty Life 2.0';

function confirmationMail(link: string): string {
  return [
    'Hallo,',
    '',
    'bitte bestätige deine E-Mail-Adresse, indem du diesen Link öffnest:',
    '',
    link,
    '',
    'Der Link ist 24 Stunden gültig und kann einmal benutzt werden.',
    'Wenn du dich nicht registriert hast, kannst du diese Nachricht ignorieren —',
    'es wurde dann kein Konto mit dieser Adresse angelegt.',
    '',
    'Nifty Life 2.0',
  ].join('\n');
}

export async function registerAction(
  _previous: AuthState,
  form: FormData,
): Promise<AuthState> {
  const email = String(form.get('email') ?? '');
  const password = String(form.get('password') ?? '');
  const repeat = String(form.get('password_repeat') ?? '');
  const username = String(form.get('username') ?? '');

  if (password !== repeat) {
    return { error: 'Die beiden Passwörter stimmen nicht überein.' };
  }

  const result = await register(email, password, username);
  if (!result.ok) return { error: result.error };

  // Signed in immediately. Confirmation is a property of the ADDRESS, not a
  // condition of being able to look at your own account page — and the page that
  // asks you to confirm is one you have to be able to reach.
  const store = await cookies();
  store.set(
    'nifty_session',
    encodeSession({ userId: result.user.id, email: result.user.email }),
    cookieOptions(),
  );

  if (mailConfigured()) {
    const token = await issueEmailToken(result.user.id);
    await sendMail({
      to: result.user.email,
      subject: MAIL_SUBJECT,
      text: confirmationMail(publicUrl(`/verify-email?token=${encodeURIComponent(token)}`)),
    });
  }

  redirect('/register/done');
}

export async function signInAction(
  _previous: AuthState,
  form: FormData,
): Promise<AuthState> {
  const result = await authenticate(
    String(form.get('email') ?? ''),
    String(form.get('password') ?? ''),
  );

  if (!result.ok) return { error: result.error };

  const store = await cookies();
  store.set(
    'nifty_session',
    encodeSession({ userId: result.user.id, email: result.user.email }),
    cookieOptions(),
  );

  return { ok: 'Angemeldet.' };
}

/**
 * Send the confirmation link again.
 *
 * Issues a fresh token rather than resending the old one. The mail carries the
 * token itself and the database only its hash, so the previous link cannot be
 * recovered — and it should not have to be: a new link is strictly better than a
 * remembered one, because a token that somebody saw on a screen they no longer
 * own is the token you least want still working.
 */
export async function resendConfirmationAction(
  _previous: AuthState,
  _form: FormData,
): Promise<AuthState> {
  const { currentAccount } = await import('@/lib/auth');
  const account = await currentAccount();
  if (!account) return { error: 'Bitte melde dich zuerst an.' };

  if (account.user.emailVerifiedAt) {
    return { ok: 'Deine Adresse ist bereits bestätigt.' };
  }

  if (!mailConfigured()) {
    // Said plainly rather than reported as a failed send: the difference between
    // "this server cannot send mail at all" and "this attempt bounced" matters to
    // somebody deciding whether to try again in ten minutes.
    return { error: 'Auf diesem Server ist kein E-Mail-Versand eingerichtet.' };
  }

  const token = await issueEmailToken(account.user.id);
  const sent = await sendMail({
    to: account.user.email,
    subject: MAIL_SUBJECT,
    text: confirmationMail(publicUrl(`/verify-email?token=${encodeURIComponent(token)}`)),
  });

  if (!sent.ok) return { error: sent.error ?? 'Die E-Mail konnte nicht versendet werden.' };

  return { ok: 'Neuer Bestätigungslink verschickt.' };
}