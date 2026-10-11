import Link from 'next/link';

import { buttonVariants } from '@/components/ui';
import { Card } from '@/components/ui/card';

export const metadata = { title: 'Abgemeldet — Nifty Life 2.0' };

/**
 * The page after the logout route has cleared the session cookie.
 *
 * Logout is a GET (the navbar link), and a GET that mutates state is already
 * a small smell; redirecting to a "you're out" page is the only way to
 * give the user a landing surface that is not the home page. Two doors
 * forward: sign back in, or carry on browsing the public site.
 */
export default function LogoutDonePage() {
  return (
    <div className="flex min-h-svh w-full items-start justify-center p-6 md:p-10">
      <div className="w-full max-w-sm">
        <Card className="mx-5 sm:mx-6">
          <h1 className="mt-0">Abgemeldet</h1>
          <p>
            Du bist nicht mehr angemeldet. Deine Sitzung auf diesem Gerät ist
            beendet.
          </p>
          <p className="mb-0">
            <Link className={buttonVariants()} href="/login">
              Wieder anmelden
            </Link>
          </p>
        </Card>
      </div>
    </div>
  );
}
