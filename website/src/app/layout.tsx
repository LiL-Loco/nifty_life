import type { Metadata } from 'next';
import Link from 'next/link';

import { currentSession } from '@/lib/auth';
import { isStaff } from '@/lib/identity';

import './globals.css';

export const metadata: Metadata = {
  title: 'Nifty Life 2.0',
  description:
    'Ein Roleplay-Server fürs Wochenende. Bewerben, Status prüfen, P&R lesen.',
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  // The team link is rendered only for staff, not merely hidden behind a URL.
  // A nav entry nobody can click tells a stranger the admin area exists; the
  // refusal page under /admin already covers a moderator who goes there
  // directly.
  const session = await currentSession();
  const showTeamLink = session ? await isStaff(session.discordId) : false;

  return (
    <html lang="de">
      <body>
        <header className="site-header">
          <Link href="/" className="wordmark">
            Nifty Life <span>2.0</span>
          </Link>
          <nav>
            <Link href="/apply">Bewerbung</Link>
            <Link href="/status">Status</Link>
            <Link href="/peeper">P&amp;R</Link>
            {showTeamLink ? <Link href="/admin">Team</Link> : null}
          </nav>
        </header>

        <main>{children}</main>

        <footer className="site-footer">
          <p>
            Freitag 19:00 bis Sonntag 22:00. In der Zwischenzeit geht nichts
            verloren.
          </p>
        </footer>
      </body>
    </html>
  );
}