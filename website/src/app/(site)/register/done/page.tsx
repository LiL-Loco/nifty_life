import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { Alert, Card, buttonVariants } from '@/components/ui';
import { mailConfigured } from '@/lib/mailer';

export const metadata = { title: 'Danke — Nifty Life 2.0' };

/**
 * The page after the registration form has been accepted.
 *
 * Three things need to happen before somebody can apply:
 *
 *   1. Open the confirmation mail and click the link. The link is single-use
 *      and 24 hours valid; if it expires, /account has a "send again" button.
 *   2. Link a Discord account. The application runs under a Discord ID, and the
 *      game server gates on `accounts.discord_id`. Without a link there is
 *      nothing to apply for, and the form on /apply refuses with a clear
 *      "Discord fehlt noch" card.
 *   3. Sign in. The session lives on the cookie set by the register action, so
 *      this page itself is signed in. /account is the next stop.
 *
 * The list intentionally does not mention any of the "is staff" details. A
 * freshly registered account is a future applicant, not a moderator, and
 * the team area is irrelevant until somebody hands them the role.
 */
export default async function RegisterDonePage() {
  const account = await currentAccount();
  if (!account) redirect('/login');

  return (
    <div className="flex min-h-svh w-full items-start justify-center p-6 md:p-10">
      <div className="w-full max-w-md">
        <Card className="mx-5 sm:mx-6">
          <h1 className="mt-0">Danke fürs Registrieren</h1>
          <p>
            Dein Konto <strong>{account.user.email}</strong> ist angelegt.
            Bevor du dich bewerben kannst, sind noch zwei Schritte nötig.
          </p>

          <ol className="my-0 ml-4 list-decimal pl-0.5 text-sm">
            <li>
              <strong>Bestätige deine E-Mail-Adresse.</strong>{' '}
              {mailConfigured() ? (
                <>
                  Wir haben dir einen Link an{' '}
                  <span className="font-mono text-xs">{account.user.email}</span>{' '}
                  geschickt. Klick ihn an, um die Adresse zu bestätigen — der
                  Link ist 24 Stunden gültig und kann nur einmal benutzt werden.
                </>
              ) : (
                <>
                  Auf diesem Server ist gerade kein E-Mail-Versand
                  eingerichtet. Ohne Bestätigung kannst du dich nicht
                  bewerben; sobald der Versand läuft, fordere im Konto
                  einen neuen Bestätigungslink an.
                </>
              )}
            </li>
            <li>
              <strong>Verknüpfe dein Discord-Konto.</strong>{' '}
              Die Bewerbung läuft unter einer Discord-Kennung. Im Konto
              findest du den Knopf dafür.
            </li>
            <li>
              <strong>Bewirb dich.</strong> Sobald beides erledigt ist, kannst du
              das Formular ausfüllen.
            </li>
          </ol>

          {!mailConfigured() ? (
            <Alert variant="destructive" role="alert" className="mt-2">
              Hinweis: Auf diesem Server ist kein E-Mail-Versand eingerichtet.
              Du kannst dich ohne bestätigte Adresse nicht bewerben.
            </Alert>
          ) : null}

          <p className="mb-0 mt-2">
            <Link className={buttonVariants()} href="/account">
              Weiter zu deinem Konto
            </Link>
          </p>
        </Card>
      </div>
    </div>
  );
}
