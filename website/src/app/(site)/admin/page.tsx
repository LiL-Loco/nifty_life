import Link from 'next/link';

import { queue, queueCounts } from '@/lib/admin';
import type { ApplicationStatus } from '@/lib/applications';

export const dynamic = 'force-dynamic';

const LABELS: Record<string, string> = {
  submitted: 'neu',
  under_review: 'in Prüfung',
  approved: 'freigegeben',
  rejected: 'abgelehnt',
};

/** Fixed set, never taken from the query string unchecked. */
const FILTERS: (ApplicationStatus | null)[] = [
  null,
  'submitted',
  'under_review',
  'approved',
  'rejected',
];

function isFilter(value: string): value is ApplicationStatus {
  return FILTERS.includes(value as ApplicationStatus);
}

function formatDate(value: string | null): string {
  if (!value) return '—';
  // Rendered by the server, in German, from a database DATETIME. Not a locale
  // guess at the browser: the reviewer is the one person who must not be shown
  // an ambiguous date.
  return value.replace('T', ' ').slice(0, 16);
}

export default async function AdminQueue({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const params = await searchParams;
  const requested = params.status ?? 'all';
  const active: ApplicationStatus | null = isFilter(requested) ? requested : null;

  const [entries, counts] = await Promise.all([queue(active), queueCounts()]);

  return (
    <>
      <h1>Bewerbungen</h1>

      <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', marginBottom: '1.5rem' }}>
        {FILTERS.map((filter) => {
          const key = filter ?? 'all';
          const label = filter === null ? 'alle' : LABELS[filter];
          const count = filter === null ? null : (counts[filter] ?? 0);
          return (
            <Link
              key={key}
              href={filter === null ? '/admin' : `/admin?status=${filter}`}
              className={filter === active ? 'button' : 'button secondary'}
            >
              {label}
              {count !== null ? ` (${count})` : ''}
            </Link>
          );
        })}
      </div>

      {entries.length === 0 ? (
        <div className="card">
          <p className="small muted">Keine Bewerbungen in dieser Ansicht.</p>
        </div>
      ) : (
        <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr>
                <th style={cellHead}>Eingegangen</th>
                <th style={cellHead}>Discord-ID</th>
                <th style={cellHead}>Status</th>
                <th style={cellHead}>Entschieden</th>
                <th style={cellHead}></th>
              </tr>
            </thead>
            <tbody>
              {entries.map((entry) => (
                <tr key={entry.id}>
                  <td style={cell}>{formatDate(entry.submitted_at)}</td>
                  <td style={{ ...cell, fontFamily: 'monospace' }}>{entry.discord_id}</td>
                  <td style={cell}>{LABELS[entry.status] ?? entry.status}</td>
                  <td style={{ ...cell, color: 'var(--muted)' }}>
                    {formatDate(entry.reviewed_at)}
                    {entry.reviewed_by_discord_id ? (
                      <span style={{ display: 'block', fontSize: '0.8em' }}>
                        von {entry.reviewed_by_discord_id}
                      </span>
                    ) : null}
                  </td>
                  <td style={{ ...cell, textAlign: 'right' }}>
                    <Link href={`/admin/${entry.id}`}>ansehen</Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
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