import Link from 'next/link';

import { queue, queueCounts } from '@/lib/admin';
import type { ApplicationStatus } from '@/lib/applications';
import {
  Card,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  buttonVariants,
} from '@/components/ui';

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
      <h1 className="px-5 sm:px-6">Bewerbungen</h1>
      <p className="mb-8 px-5 text-muted-foreground sm:px-6">
        {entries.length === 0
          ? 'Keine offenen Bewerbungen.'
          : `${entries.length} ${entries.length === 1 ? 'Bewerbung' : 'Bewerbungen'} in dieser Ansicht.`}
      </p>

      <div className="mb-6 flex flex-wrap gap-2 px-5 sm:px-6">
        {FILTERS.map((filter) => {
          const key = filter ?? 'all';
          const label = filter === null ? 'alle' : LABELS[filter];
          const count = filter === null ? null : (counts[filter] ?? 0);
          return (
            <Link
              key={key}
              href={filter === null ? '/admin' : `/admin?status=${filter}`}
              className={buttonVariants({
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
        <Card className="mx-5 sm:mx-6">
          <p className="text-sm text-muted-foreground">
            Keine Bewerbungen in dieser Ansicht.
          </p>
        </Card>
      ) : (
        <Card className="overflow-hidden p-0 mx-5 sm:mx-6">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Eingegangen</TableHead>
                <TableHead>E-Mail</TableHead>
                <TableHead>Discord</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Entschieden</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {entries.map((entry) => (
                <TableRow key={entry.id}>
                  <TableCell>{formatDate(entry.submitted_at)}</TableCell>
                  <TableCell>
                    {entry.email ?? (
                      // The one application that predates portal accounts. Said
                      // out loud rather than left blank, so nobody reads the
                      // empty cell as a bug.
                      <span className="text-sm text-muted-foreground">kein Portal-Konto</span>
                    )}
                  </TableCell>
                  <TableCell className="font-mono">{entry.discord_id}</TableCell>
                  <TableCell>{LABELS[entry.status] ?? entry.status}</TableCell>
                  <TableCell className="text-muted-foreground">
                    {formatDate(entry.reviewed_at)}
                    {entry.reviewed_by_discord_id ? (
                      <span className="block text-[0.8em]">
                        von {entry.reviewed_by_discord_id}
                      </span>
                    ) : null}
                  </TableCell>
                  <TableCell className="text-right">
                    <Link href={`/admin/${entry.id}`}>ansehen</Link>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      )}
    </>
  );
}
