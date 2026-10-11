import Link from 'next/link';

import { registrations } from '@/lib/users';
import {
  Card,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui';

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
      <h1 className="px-5 sm:px-6">Registrierungen</h1>
      <p className="mb-8 px-5 text-muted-foreground sm:px-6">
        {rows.length} {rows.length === 1 ? 'Konto' : 'Konten'}, neueste zuerst.
      </p>

      {rows.length === 0 ? (
        <Card>
          <p className="text-sm text-muted-foreground">
            Noch niemand hat sich registriert.
          </p>
        </Card>
      ) : (
        <Card className="overflow-hidden p-0 mx-5 sm:mx-6">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>E-Mail</TableHead>
                <TableHead>Adresse</TableHead>
                <TableHead>Discord</TableHead>
                <TableHead>Rolle</TableHead>
                <TableHead>Bewerbung</TableHead>
                <TableHead>Registriert</TableHead>
                <TableHead>Letzte Anmeldung</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((row) => (
                <TableRow key={row.id}>
                  <TableCell>
                    <Link
                      href={`/admin/users/${row.id}`}
                      className="text-foreground hover:underline"
                    >
                      {row.email}
                    </Link>
                  </TableCell>
                  <TableCell>
                    {row.email_verified_at ? (
                      <span className="text-success">bestätigt</span>
                    ) : (
                      <span className="text-muted-foreground">offen</span>
                    )}
                  </TableCell>
                  <TableCell>
                    {row.username ?? <span className="text-muted-foreground">—</span>}
                  </TableCell>
                  <TableCell>
                    {row.is_staff ? (
                      <span className="text-primary">Staff</span>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </TableCell>
                  <TableCell>
                    {row.application_status ?? (
                      <span className="text-muted-foreground">keine</span>
                    )}
                  </TableCell>
                  <TableCell>{formatDate(row.created_at)}</TableCell>
                  <TableCell className="text-muted-foreground">
                    {formatDate(row.last_login_at)}
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
