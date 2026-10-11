import type { Metadata } from 'next';
import Link from 'next/link';

import './globals.css';

export const metadata: Metadata = {
  title: 'Nifty Life 2.0',
  description: 'A weekend roleplay server. Apply, check your status, read Peeper.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <header className="site-header">
          <Link href="/" className="wordmark">
            Nifty Life <span>2.0</span>
          </Link>
          <nav>
            <Link href="/apply">Apply</Link>
            <Link href="/status">Status</Link>
            <Link href="/peeper">Peeper</Link>
          </nav>
        </header>

        <main>{children}</main>

        <footer className="site-footer">
          <p>Friday 19:00 to Sunday 22:00. Nothing is lost while the world sleeps.</p>
        </footer>
      </body>
    </html>
  );
}