import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentSession } from '@/lib/auth';
import { isStaff } from '@/lib/identity';

export const metadata: Metadata = { title: 'Admin — Nifty Life 2.0' };

/**
 * The gate every /admin page calls first.
 *
 * `currentSession()` throws for "not signed in" and `isStaff()` answers the
 * remaining question, so there are exactly three outcomes handled in one place:
 * signed out, signed in but not staff, staff.
 *
 * Note WHAT decides staff: the `staff` mirror, written only by the Discord bot
 * from the staff role. It used to be `characters.is_staff` through `web_links`,
 * which meant nobody could reach this page until they had played the game — and
 * since no client has ever connected, nobody could reach it at all.
 */
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const session = await currentSession();

  if (!session) {
    redirect('/login');
  }

  if (!(await isStaff(session.discordId))) {
    // A refusal, not a 404. Telling a stranger that this path exists is not a
    // leak worth preventing — the landing page says the area exists — but
    // pretending the page is missing only makes a real moderator file a bug
    // report against a working site.
    return (
      <div className="card">
        <h1 style={{ marginTop: 0 }}>Kein Zugriff</h1>
        <p>
          Dein Discord-Konto <strong>{session.username}</strong> hat keine
          Teamrolle, deshalb ist dieser Bereich gesperrt.
        </p>
        <p className="small muted">
          Wenn das nicht stimmt: Lass dir im Discord die Teamrolle geben, warte
          einen Moment — der Bot synchronisiert sie sofort — und lade die Seite neu.
        </p>
        <p style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
          <Link className="button secondary" href="/">
            Zur Startseite
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
      <p className="small muted">
        Team-Bereich · angemeldet als <strong>{session.username}</strong>{' '}
        <Link href="/auth/logout">abmelden</Link>
      </p>
      {children}
    </div>
  );
}