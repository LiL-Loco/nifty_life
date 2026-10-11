import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { Card, buttonVariants } from '@/components/ui';

export const metadata: Metadata = { title: 'Admin — Nifty Life 2.0' };

/**
 * The gate every /admin page calls first.
 *
 * Staff is a DISCORD ROLE (migration 011), mirrored into the `staff` table by the
 * bot. That is checked against the account's LINKED Discord ID, which is why an
 * account without one is never staff: there is nothing to look the role up by.
 *
 * The page chrome (logo, nav links, user identity, logout) lives in the
 * site-level Navbar. For a staff visitor the Navbar already shows
 * Bewerbungen / Registrierungen / P&R, so the admin area needs no second tab
 * strip on top of its pages.
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
      <Card className="mx-5 sm:mx-6">
        <h1 className="px-5 sm:px-6 -mx-5 sm:-mx-6 pt-0">Kein Zugriff</h1>
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
        <p className="text-sm text-muted-foreground">
          Wenn das nicht stimmt: Lass dir im Discord die Teamrolle geben, warte
          einen Moment — der Bot synchronisiert sie sofort — und lade die Seite neu.
        </p>
        <p className="flex flex-wrap gap-3">
          <Link className={buttonVariants({ variant: 'secondary' })} href="/account">
            Zur Kontoseite
          </Link>
          <Link className={buttonVariants({ variant: 'secondary' })} href="/auth/logout">
            Abmelden
          </Link>
        </p>
      </Card>
    );
  }

  return <>{children}</>;
}
