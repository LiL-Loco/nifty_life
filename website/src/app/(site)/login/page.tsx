import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { signInAction } from '@/lib/account-actions';
import { Card, Notice } from '@/components/ui';
import AuthForm from './form';

export const metadata: Metadata = { title: 'Anmelden — Nifty Life 2.0' };

const ERRORS: Record<string, string> = {
  'link-needs-account':
    'Zum Verknüpfen eines Discord-Kontos musst du angemeldet sein.',
};

/**
 * Sign in with email and password.
 *
 * There is no Discord button here, and that is the point of the whole revision:
 * signing in proves you own a MAILBOX, and Discord is attached separately on
 * /account. The old flow used Discord as the login, which made having an account
 * depend on already having the thing you were applying for.
 *
 * A signed-in visitor is sent on rather than shown a form they would only get
 * wrong — /account is the page that tells them what is still missing.
 */
export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const [account, params] = await Promise.all([currentAccount(), searchParams]);
  if (account) redirect('/account');

  const error = params.error ? ERRORS[params.error] : undefined;

  return (
    <Card className="max-w-[26rem]">
      <h1 className="mt-0">Anmelden</h1>

      {error ? (
        <Notice tone="error" role="alert">
          {error}
        </Notice>
      ) : null}

      <AuthForm action={signInAction} submitLabel="Anmelden" />

      <p className="mt-6 text-sm text-muted">
        Noch kein Konto? <Link href="/register">Hier registrieren</Link>
      </p>
    </Card>
  );
}