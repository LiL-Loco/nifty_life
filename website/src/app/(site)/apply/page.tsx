import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { DISCORD_REQUIRED } from '@/lib/applications';
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
      <div className="card" style={{ maxWidth: '34rem' }}>
        <h1 style={{ marginTop: 0 }}>Noch nicht bestätigt</h1>
        <p>
          Deine E-Mail-Adresse <strong>{account.user.email}</strong> ist noch nicht
          bestätigt. Ohne bestätigte Adresse gehört eine Bewerbung zu niemandem, dem
          man antworten könnte.
        </p>
        <p style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
          <Link className="button" href="/account">
            Bestätigungslink anfordern
          </Link>
          <Link className="button secondary" href="/status">
            Mein Status
          </Link>
        </p>
      </div>
    );
  }

  if (!account.discord) {
    return (
      <div className="card" style={{ maxWidth: '34rem' }}>
        <h1 style={{ marginTop: 0 }}>Discord fehlt noch</h1>
        <p>{DISCORD_REQUIRED}</p>
        <p className="small muted">
          Die Bewerbung läuft unter einer Discord-Kennung. Das ist die Identität,
          gegen die der Spielserver beim Verbinden prüft — deshalb lässt sie sich
          nicht ohne Discord-Konto einreichen.
        </p>
        <p style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
          <Link className="button" href="/auth/discord/connect?next=/apply">
            Discord-Konto verknüpfen
          </Link>
          <Link className="button secondary" href="/account">
            Zur Kontoseite
          </Link>
        </p>
      </div>
    );
  }

  return (
    <>
      <h1>Bewerbung</h1>
      <p className="lede">
        Konto <strong>{account.user.email}</strong> · Discord{' '}
        <strong>{account.discord.username}</strong>. Die Bewerbung wird unter dieser
        Discord-Kennung abgelegt — das ist die Identität, die der Server beim
        Verbinden prüft.
      </p>

      <ApplicationForm />
    </>
  );
}