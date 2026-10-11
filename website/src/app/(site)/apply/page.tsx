import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { DISCORD_REQUIRED } from '@/lib/applications';
import { Card, buttonVariants } from '@/components/ui';
import ApplicationForm from './form';

/**
 * The application form, and the two gates in front of it.
 *
 * Both gates are stated as links to the page that fixes them rather than as a
 * dead form. Somebody who registered and has not linked Discord yet is one click
 * from applying, and telling them so is the difference between a signup funnel
 * that finishes and one that stalls on a blank screen.
 */
export default async function ApplyPage() {
  const account = await currentAccount();
  if (!account) redirect('/login');

  if (!account.user.emailVerifiedAt) {
    return (
      <Card className="max-w-[34rem]">
        <h1>Noch nicht bestätigt</h1>
        <p>
          Deine E-Mail-Adresse <strong>{account.user.email}</strong> ist noch nicht
          bestätigt. Ohne bestätigte Adresse gehört eine Bewerbung zu niemandem, dem
          man antworten könnte.
        </p>
        <p className="flex flex-wrap gap-3">
          <Link className={buttonVariants()} href="/account">
            Bestätigungslink anfordern
          </Link>
          <Link className={buttonVariants({ variant: 'secondary' })} href="/status">
            Mein Status
          </Link>
        </p>
      </Card>
    );
  }

  if (!account.discord) {
    return (
      <Card className="max-w-[34rem]">
        <h1>Discord fehlt noch</h1>
        <p>{DISCORD_REQUIRED}</p>
        <p className="text-sm text-muted-foreground">
          Die Bewerbung läuft unter einer Discord-Kennung. Das ist die Identität,
          gegen die der Spielserver beim Verbinden prüft — deshalb lässt sie sich
          nicht ohne Discord-Konto einreichen.
        </p>
        <p className="flex flex-wrap gap-3">
          <a className={buttonVariants()} href="/auth/discord/connect?next=/apply">
            Discord-Konto verknüpfen
          </a>
          <Link className={buttonVariants({ variant: 'secondary' })} href="/account">
            Zur Kontoseite
          </Link>
        </p>
      </Card>
    );
  }

  return (
    <>
      <h1 className="px-5 sm:px-6">Bewerbung</h1>
      <p className="mb-8 px-5 text-muted-foreground sm:px-6">
        Konto <strong>{account.user.email}</strong> · Discord{' '}
        <strong>{account.discord.username}</strong>. Die Bewerbung wird unter dieser
        Discord-Kennung abgelegt — das ist die Identität, die der Server beim
        Verbinden prüft.
      </p>

      <ApplicationForm />
    </>
  );
}
