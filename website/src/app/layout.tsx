import type { Metadata } from 'next';
import Link from 'next/link';

import './globals.css';

export const metadata: Metadata = {
  title: 'Nifty Life 2.0',
  description:
    'Ein Roleplay-Server fürs Wochenende. Bewerben, Status prüfen, P&R lesen.',
};

/**
 * No session check, no database, and deliberately no link to /admin here.
 *
 * The team area is reached from a pinned Discord message or by typing the URL —
 * not from the public navigation. Two reasons:
 *
 * 1. A nav entry a stranger can see but not click advertises that a moderation
 *    area exists. That is information nobody needs, and the refusal page under
 *    /admin already handles a moderator who arrives directly.
 * 2. It costs nothing. Showing that link meant an `isStaff()` query on EVERY page
 *    for every signed-in visitor, on a site that is otherwise public and
 *    read-mostly. One indexed lookup per request, to decide about one link that
 *    is now not there.
 */
export default function RootLayout({ children }: { children: React.ReactNode }) {
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