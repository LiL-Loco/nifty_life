import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';

export const metadata: Metadata = { title: 'Admin — Nifty Life 2.0' };

/**
 * The gate every /admin page calls first, plus the team navigation.
 *
 * Staff is a DISCORD ROLE (migration 011), mirrored into the `staff` table by the
 * bot. That is checked against the account's LINKED Discord ID, which is why an
 * account without one is never staff: there is nothing to look the role up by.
 *
 * The nav deliberately does NOT offer Bewerbung (apply) or Status. The team reads
 * applications; the team does not submit them, and a moderation account sitting
 * on a personal whitelist entry is exactly the confusion the split avoids. The
 * public navigation drops those two entries for staff for the same reason —
 * showing a moderator a link to a form they must not use is worse than showing
 * them nothing.
 */
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const account = await currentAccount();

  if (!account) {
    redirect('/login');
  }

  if (!account.isStaff || !account.discord) {
    // A refusal, not a 404. Telling a stranger that this path exists is not a
    // leak worth preventing — the landing page says the area exists — but
    // pretending the page is missing only makes a real moderator file a bug
    // report against a working site.
    return (
      <div className="card">
        <h1 style={{ marginTop: 0 }}>Kein Zugriff</h1>
        <p>
          Dein Konto <strong>{account.user.email}</strong> hat keine Teamrolle,
          deshalb ist dieser Bereich gesperrt.
          {!account.discord ? (
            <>
              {' '}
              Zusätzlich ist kein Discord-Konto verknüpft — die Teamrolle wird an
              Discord-Konten vergeben, nicht an E-Mail-Adressen.
            </>
          ) : null}
        </p>
        <p className="small muted">
          Wenn das nicht stimmt: Lass dir im Discord die Teamrolle geben, warte
          einen Moment — der Bot synchronisiert sie sofort — und lade die Seite neu.
        </p>
        <p style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
          <Link className="button secondary" href="/account">
            Zur Kontoseite
          </Link>
          <Link className="button secondary" href="/auth/logout">
            Abmelden
          </Link>
        </p>
      </div>
    );
  }

  return (
    <div>
      <nav className="team-nav">
        <Link href="/admin">Bewerbungen</Link>
        <Link href="/admin/users">Registrierungen</Link>
        <Link href="/peeper">P&amp;R</Link>
      </nav>

      <p className="small muted">
        Team-Bereich · {account.discord.username}{' '}
        <span className="small">({account.user.email})</span>{' '}
        <Link href="/auth/logout">abmelden</Link>
      </p>

      {children}
    </div>
  );
}