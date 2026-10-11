import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { discordConfigured } from '@/lib/config';
import { Card, buttonVariants } from '@/components/ui';

export const metadata = { title: 'Einstellungen — Nifty Life 2.0' };

/**
 * Account settings.
 *
 * The portal has few toggles today: the address confirmation and the Discord
 * link. Both are status surfaces, not preferences, but they are the
 * things a "Settings" entry in the user menu is expected to lead to. New
 * settings go here too — notifications, language, what-have-you — when
 * there is anything to add.
 */
export default async function SettingsPage() {
  const account = await currentAccount();
  if (!account) redirect('/login');

  const { user, discord } = account;

  return (
    <>
      <h1 className="px-5 sm:px-6">Einstellungen</h1>
      <p className="mb-8 px-5 text-muted-foreground sm:px-6">
        Status der Dinge, die das Portal für dich verwaltet.
      </p>

      <Card className="mx-5 sm:mx-6">
        <dl className="m-0">
          <dt className={term}>E-Mail-Adresse</dt>
          <dd className={value}>
            <span className="font-mono text-sm">{user.email}</span>
            <div className="mt-1 text-sm">
              {user.emailVerifiedAt ? (
                <span className="text-success">bestätigt</span>
              ) : (
                <span className="text-muted-foreground">
                  nicht bestätigt —{' '}
                  <Link className="underline" href="/account">
                    Bestätigungslink anfordern
                  </Link>
                </span>
              )}
            </div>
          </dd>

          <dt className={term}>Discord-Konto</dt>
          <dd className={value}>
            {discord ? (
              <>
                {discord.username}{' '}
                <span className="font-mono text-xs text-muted-foreground">
                  {discord.discordId}
                </span>
                <div className="mt-1 text-sm text-muted-foreground">
                  verknüpft am {String(discord.linkedAt).slice(0, 16).replace('T', ' ')}
                </div>
              </>
            ) : discordConfigured ? (
              <Link
                className={buttonVariants({ size: 'sm' })}
                href="/auth/discord/connect?next=/account/settings"
              >
                Discord-Konto verknüpfen
              </Link>
            ) : (
              <span className="text-muted-foreground">
                Auf diesem Server ist keine Discord-Anwendung eingerichtet.
              </span>
            )}
          </dd>
        </dl>
      </Card>
    </>
  );
}

const term = 'mt-4 text-xs uppercase tracking-[0.06em] text-muted-foreground';
const value = 'mt-1.5 mb-0';
