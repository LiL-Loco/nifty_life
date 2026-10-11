import Link from 'next/link';

import { confirmEmail } from '@/lib/users';

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
    <div className="card" style={{ maxWidth: '30rem' }}>
      <h1 style={{ marginTop: 0 }}>E-Mail-Adresse bestätigen</h1>

      {result.ok ? (
        <>
          <div className="notice ok">Deine Adresse ist bestätigt.</div>
          <p>
            <Link className="button" href="/account">
              Weiter zu deinem Konto
            </Link>
          </p>
        </>
      ) : (
        <>
          <div className="notice error">
            Dieser Bestätigungslink ist ungültig oder abgelaufen.
          </div>
          <p className="small muted">
            Ein Link funktioniert genau einmal und ist 24 Stunden gültig. Ist er
            abgelaufen, hol dir auf der Kontoseite einen neuen.
          </p>
          <p style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
            <Link className="button secondary" href="/account">
              Neuen Link anfordern
            </Link>
            <Link className="button secondary" href="/login">
              Anmelden
            </Link>
          </p>
        </>
      )}
    </div>
  );
}