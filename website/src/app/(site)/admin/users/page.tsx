import Link from 'next/link';

import { registrations } from '@/lib/users';
import { Card, Td, Th } from '@/components/ui';

export const dynamic = 'force-dynamic';

/**
 * Who has an account.
 *
 * Separate from the application queue because the two questions are different and
 * have different populations. The queue is "who asked to play"; this is "who made
 * an account", and the interesting rows here are the ones that never reached the
 * queue: an address never confirmed, a Discord never linked, an account that
 * registered and vanished.
 *
 * That last one is why `last_login_at` is on this page. Registration alone says
 * somebody typed a form; a last login says they came back. A list of accounts
 * with no last-login column cannot tell "signed up and left" from "signed up and
 * is using it".
 */
function formatDate(value: string | null): string {
  if (!value) return '—';
  return value.replace('T', ' ').slice(0, 16);
}

export default async function AdminUsers() {
  const rows = await registrations();

  return (
    <>
      <h1>Registrierungen</h1>
      <p className="mb-8 text-muted">
        {rows.length} {rows.length === 1 ? 'Konto' : 'Konten'}, neueste zuerst.
      </p>

      {rows.length === 0 ? (
        <Card>
          <p className="mb-0 text-sm text-muted">Noch niemand hat sich registriert.</p>
        </Card>
      ) : (
        <Card padding="flush">
          <table className="w-full border-collapse">
            <thead>
              <tr>
                <Th>E-Mail</Th>
                <Th>Adresse</Th>
                <Th>Discord</Th>
                <Th>Bewerbung</Th>
                <Th>Registriert</Th>
                <Th>Letzte Anmeldung</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id}>
                  <Td>{row.email}</Td>
                  <Td>
                    {row.email_verified_at ? (
                      <span className="text-ok">bestätigt</span>
                    ) : (
                      <span className="text-muted">offen</span>
                    )}
                  </Td>
                  <Td className="font-mono">
                    {row.discord_id ?? <span className="text-muted">—</span>}
                  </Td>
                  <Td>
                    {row.application_status ?? (
                      <span className="text-muted">keine</span>
                    )}
                  </Td>
                  <Td>{formatDate(row.created_at)}</Td>
                  <Td className="text-muted">{formatDate(row.last_login_at)}</Td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}

      <p className="text-sm text-muted">
        <Link href="/admin">← zu den Bewerbungen</Link>
      </p>
    </>
  );
}