import type { Metadata } from 'next';
import Link from 'next/link';

import './globals.css';

export const metadata: Metadata = {
  title: 'Nifty Life 2.0',
  description:
    'Ein Roleplay-Server fürs Wochenende. Bewerben, Status prüfen, Peeper lesen.',
};

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