import Link from 'next/link';

import { queue, queueCounts } from '@/lib/admin';
import type { ApplicationStatus } from '@/lib/applications';
import { Card, Td, Th, buttonLinkClass } from '@/components/ui';

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
  if (!value) return '-';
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

      <div className="mb-6 flex flex-wrap gap-2">
        {FILTERS.map((filter) => {
          const key = filter ?? 'all';
          const label = filter === null ? 'alle' : LABELS[filter];
          const count = filter === null ? null : (counts[filter] ?? 0);
          return (
            <Link
              key={key}
              href={filter === null ? '/admin' : `/admin?status=${filter}`}
              className={buttonLinkClass({
                variant: filter === active ? 'default' : 'secondary',
                size: 'sm',
              })}
            >
              {label}
              {count !== null ? ` (${count})` : ''}
            </Link>
          );
        })}
      </div>

      {entries.length === 0 ? (
        <Card>
          <p className="mb-0 text-sm text-muted">Keine Bewerbungen in dieser Ansicht.</p>
        </Card>
      ) : (
        <Card padding="flush">
          <table className="w-full border-collapse">
            <thead>
              <tr>
                <Th>Eingegangen</Th>
                <Th>E-Mail</Th>
                <Th>Discord</Th>
                <Th>Status</Th>
                <Th>Entschieden</Th>
                <Th />
              </tr>
            </thead>
            <tbody>
              {entries.map((entry) => (
                <tr key={entry.id}>
                  <Td>{formatDate(entry.submitted_at)}</Td>
                  <Td>
                    {entry.email ?? (
                      // The one application that predates portal accounts. Said
                      // out loud rather than left blank, so nobody reads the
                      // empty cell as a bug.
                      <span className="text-sm text-muted">kein Portal-Konto</span>
                    )}
                  </Td>
                  <Td className="font-mono">{entry.discord_id}</Td>
                  <Td>{LABELS[entry.status] ?? entry.status}</Td>
                  <Td className="text-muted">
                    {formatDate(entry.reviewed_at)}
                    {entry.reviewed_by_discord_id ? (
                      <span className="block text-[0.8em]">
                        von {entry.reviewed_by_discord_id}
                      </span>
                    ) : null}
                  </Td>
                  <Td className="text-right">
                    <Link href={`/admin/${entry.id}`}>ansehen</Link>
                  </Td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}
    </>
  );
}