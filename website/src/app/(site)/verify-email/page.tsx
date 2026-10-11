import Link from 'next/link';

import { confirmEmail } from '@/lib/users';
import { Card, Notice, buttonLinkClass } from '@/components/ui';

/**
 * The confirmation link target.
 *
 * A page rather than a redirect so the person finds out what happened. A GET is
 * correct for this: the link is read from an email client, where a link that only
 * works on a POST cannot be followed at all.
 *
 * The token is single-use and the claim runs inside the stored procedure
 * `confirm_portal_email` (migration 017) — the website account cannot write
 * `email_verified_at` at all, so this route is not merely the polite way to
 * confirm, it is the only way.
 */
export default async function VerifyEmailPage({
  searchParams,
}: {
  searchParams: Promise<{ token?: string }>;
}) {
  const { token } = await searchParams;

  const result = token ? await confirmEmail(token) : { ok: false as const };

  return (
    <Card className="max-w-[30rem]">
      <h1 className="mt-0">E-Mail-Adresse bestätigen</h1>

      {result.ok ? (
        <>
          <Notice tone="ok">Deine Adresse ist bestätigt.</Notice>
          <p>
            <Link className={buttonLinkClass()} href="/account">
              Weiter zu deinem Konto
            </Link>
          </p>
        </>
      ) : (
        <>
          <Notice tone="error" role="alert">
            Dieser Bestätigungslink ist ungültig oder abgelaufen.
          </Notice>
          <p className="text-sm text-muted">
            Ein Link funktioniert genau einmal und ist 24 Stunden gültig. Ist er
            abgelaufen, hol dir auf der Kontoseite einen neuen.
          </p>
          <p className="flex flex-wrap gap-3">
            <Link className={buttonLinkClass({ variant: 'secondary' })} href="/account">
              Neuen Link anfordern
            </Link>
            <Link className={buttonLinkClass({ variant: 'secondary' })} href="/login">
              Anmelden
            </Link>
          </p>
        </>
      )}
    </Card>
  );
}