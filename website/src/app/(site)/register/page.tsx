import type { Metadata } from 'next';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { registerAction } from '@/lib/account-actions';
import { mailConfigured } from '@/lib/mailer';
import { LoginForm } from '@/components/login-form';

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
    <div className="flex min-h-svh w-full items-start justify-center p-6 md:p-10">
      <div className="w-full max-w-sm">
        <LoginForm action={registerAction} mode="register" />
        <p className="text-muted-foreground mt-4 text-center text-sm">
          {mailConfigured()
            ? 'Wir schicken dir danach einen Link, mit dem du deine Adresse bestätigst.'
            : 'Hinweis: Auf diesem Server ist derzeit kein E-Mail-Versand eingerichtet, das Konto wird aber trotzdem angelegt.'}
        </p>
      </div>
    </div>
  );
}
