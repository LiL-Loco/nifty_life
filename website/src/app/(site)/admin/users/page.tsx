import Link from 'next/link';

import { registrations } from '@/lib/users';

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
      <p className="lede">
        {rows.length} {rows.length === 1 ? 'Konto' : 'Konten'}, neueste zuerst.
      </p>

      {rows.length === 0 ? (
        <div className="card">
          <p className="small muted">Noch niemand hat sich registriert.</p>
        </div>
      ) : (
        <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr>
                <th style={cellHead}>E-Mail</th>
                <th style={cellHead}>Adresse</th>
                <th style={cellHead}>Discord</th>
                <th style={cellHead}>Bewerbung</th>
                <th style={cellHead}>Registriert</th>
                <th style={cellHead}>Letzte Anmeldung</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id}>
                  <td style={{ ...cell, fontFamily: 'inherit' }}>{row.email}</td>
                  <td style={cell}>
                    {row.email_verified_at ? (
                      <span style={{ color: 'var(--ok)' }}>bestätigt</span>
                    ) : (
                      <span style={{ color: 'var(--muted)' }}>offen</span>
                    )}
                  </td>
                  <td style={{ ...cell, fontFamily: 'monospace' }}>
                    {row.discord_id ?? (
                      <span style={{ color: 'var(--muted)', fontFamily: 'inherit' }}>
                        —
                      </span>
                    )}
                  </td>
                  <td style={{ ...cell, fontFamily: 'inherit' }}>
                    {row.application_status ?? (
                      <span style={{ color: 'var(--muted)' }}>keine</span>
                    )}
                  </td>
                  <td style={cell}>{formatDate(row.created_at)}</td>
                  <td style={{ ...cell, color: 'var(--muted)' }}>
                    {formatDate(row.last_login_at)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <p className="small muted">
        <Link href="/admin">← zu den Bewerbungen</Link>
      </p>
    </>
  );
}

const cell: React.CSSProperties = {
  padding: '0.6rem 0.8rem',
  borderTop: '1px solid var(--line)',
  fontSize: '0.9rem',
  verticalAlign: 'top',
};

const cellHead: React.CSSProperties = {
  ...cell,
  borderTop: 'none',
  textAlign: 'left',
  fontSize: '0.75rem',
  textTransform: 'uppercase',
  letterSpacing: '0.06em',
  color: 'var(--muted)',
};