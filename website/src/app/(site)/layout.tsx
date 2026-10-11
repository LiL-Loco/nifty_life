import Link from 'next/link';

/**
 * The portal's chrome — every page inside `app/(site)`.
 *
 * Navigation is public-only on purpose. The team area is not in it: a nav entry
 * a stranger can see but not click advertises that a moderation area exists, and
 * showing it meant an `isStaff()` query on every page for every signed-in visitor
 * on a site that is otherwise public and read-mostly. The team link lives in
 * Discord and in the bot's startup output.
 */
export default function SiteLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
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
        <p>Freitag 19:00 bis Sonntag 22:00. In der Zwischenzeit geht nichts verloren.</p>
      </footer>
    </>
  );
}