import Link from 'next/link';

import { confirmEmail } from '@/lib/users';
import { Alert, buttonVariants } from '@/components/ui';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Field, FieldGroup } from '@/components/ui/field';

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
    <div className="flex min-h-svh w-full items-center justify-center p-6 md:p-10">
      <div className="w-full max-w-sm">
        <Card>
          <CardHeader>
            <CardTitle>E-Mail-Adresse bestätigen</CardTitle>
            {result.ok ? (
              <CardDescription>Deine Adresse ist bestätigt.</CardDescription>
            ) : (
              <CardDescription>
                Dieser Bestätigungslink ist ungültig oder abgelaufen.
              </CardDescription>
            )}
          </CardHeader>
          <CardContent>
            {result.ok ? (
              <Alert className="border-success/40 bg-success/10 text-success [&>svg]:text-success">
                Alles klar. Du kannst dich jetzt anmelden oder direkt zum Konto
                gehen.
              </Alert>
            ) : (
              <Alert variant="destructive" role="alert">
                Ein Link funktioniert genau einmal und ist 24 Stunden gültig. Ist
                er abgelaufen, hol dir auf der Kontoseite einen neuen.
              </Alert>
            )}

            <FieldGroup className="mt-6">
              {result.ok ? (
                <Field>
                  <Link className={buttonVariants()} href="/account">
                    Weiter zu deinem Konto
                  </Link>
                </Field>
              ) : (
                <Field>
                  <Link className={buttonVariants()} href="/account">
                    Neuen Link anfordern
                  </Link>
                  <Link
                    className={buttonVariants({ variant: 'secondary' })}
                    href="/login"
                  >
                    Anmelden
                  </Link>
                </Field>
              )}
            </FieldGroup>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
