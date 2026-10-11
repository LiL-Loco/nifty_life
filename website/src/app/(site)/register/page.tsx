import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { registerAction } from '@/lib/account-actions';
import { mailConfigured } from '@/lib/mailer';
import AuthForm from '../login/form';

export const metadata: Metadata = { title: 'Registrieren — Nifty Life 2.0' };

/**
 * Make an account.
 *
 * Email and password, decided here and nowhere else. Discord comes afterwards and
 * is what an APPLICATION needs — a person can hold an account, read the rulebook
 * and decide not to apply, and none of that needs a Discord account.
 *
 * If SMTP is not configured the form still works and the account is still made.
 * The missing mail is stated on the account page rather than here, because this
 * page has already succeeded by the time anybody could notice.
 */
export default async function RegisterPage() {
  if (await currentAccount()) redirect('/account');

  return (
    <div className="card" style={{ maxWidth: '26rem' }}>
      <h1 style={{ marginTop: 0 }}>Registrieren</h1>

      <p className="small muted" style={{ marginTop: 0 }}>
        Das Konto gehört dir. Bewerben kannst du dich danach, und dafür brauchst du
        zusätzlich ein verknüpftes Discord-Konto.
      </p>

      <AuthForm action={registerAction} submitLabel="Konto anlegen" showRepeat />

      <p className="small muted" style={{ marginTop: '1.5rem' }}>
        {mailConfigured()
          ? 'Wir schicken dir danach einen Link, mit dem du deine Adresse bestätigst.'
          : 'Hinweis: Auf diesem Server ist derzeit kein E-Mail-Versand eingerichtet, das Konto wird aber trotzdem angelegt.'}
      </p>

      <p className="small muted">
        Schon ein Konto? <Link href="/login">Hier anmelden</Link>
      </p>
    </div>
  );
}