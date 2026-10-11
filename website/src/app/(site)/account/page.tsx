import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { discordConfigured } from '@/lib/config';
import { Alert, Card, buttonVariants } from '@/components/ui';
import ResendButton from './resend-button';

const ERRORS: Record<string, string> = {
  'link-failed': 'Die Verknüpfung wurde nicht abgeschlossen. Bitte versuch es noch einmal.',
  'discord-taken':
    'Dieses Discord-Konto ist bereits mit einem Portal-Konto verknüpft. Ein Discord-Konto gehört zu genau einem Portal-Konto.',
  'discord-not-configured':
    'Auf diesem Server ist keine Discord-Anwendung eingerichtet, deshalb lässt sich nichts verknüpfen.',
  'invalid-discord': 'Discord hat ein unbrauchbares Konto zurückgegeben.',
  'write-failed': 'Die Verknüpfung konnte nicht gespeichert werden.',
};

/**
 * The account page: what is signed in, what is still missing.
 *
 * This is the page that replaced "Discord was the login". It answers three
 * questions in one place — who am I, is my address confirmed, is Discord linked —
 * because those three are the preconditions of everything else and a person
 * should not have to learn them by hitting a refusal on the application form.
 *
 * Everything here is read from the database. Nothing on this page is rendered out
 * of the cookie.
 */
export default async function AccountPage({
  searchParams,
}: {
  searchParams: Promise<{ linked?: string; error?: string }>;
}) {
  const [account, params] = await Promise.all([currentAccount(), searchParams]);

  if (!account) redirect('/login');

  const { user, discord, isStaff } = account;
  const error = params.error ? ERRORS[params.error] : undefined;

  return (
    <>
      <h1 className="px-5 sm:px-6">Dein Konto</h1>

      {params.linked ? (
        <Alert className="border-success/40 bg-success/10 text-success [&>svg]:text-success">
          Discord-Konto verknüpft. Damit kannst du dich bewerben.
        </Alert>
      ) : null}
      {error ? (
        <Alert variant="destructive" role="alert">
          {error}
        </Alert>
      ) : null}

      <Card className="mx-5 sm:mx-6">
        <dl className="m-0">
          {user.username ? (
            <>
              <dt className={term}>Anzeigename</dt>
              <dd className={value}>{user.username}</dd>
            </>
          ) : null}

          <dt className={term}>E-Mail</dt>
          <dd className={value}>{user.email}</dd>

          <dt className={term}>Adresse bestätigt</dt>
          <dd className={value}>
            {user.emailVerifiedAt ? (
              <>ja · {String(user.emailVerifiedAt).slice(0, 16).replace('T', ' ')}</>
            ) : (
              <>
                nein
                <div className="mt-3 text-sm text-muted-foreground">
                  Ohne bestätigte Adresse kannst du dich nicht bewerben.
                  <div className="mt-2.5">
                    <ResendButton />
                  </div>
                </div>
              </>
            )}
          </dd>

          <dt className={term}>Discord</dt>
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
            ) : (
              <>
                nicht verknüpft
                <div className="mt-2 text-sm text-muted-foreground">
                  Die Bewerbung läuft unter einer Discord-Kennung — das ist die
                  Identität, die der Spielserver beim Verbinden prüft.
                </div>
                <div className="mt-3">
                  {discordConfigured ? (
                    <Link
                      className={buttonVariants()}
                      href="/auth/discord/connect?next=/account"
                    >
                      Discord-Konto verknüpfen
                    </Link>
                  ) : (
                    <span className="text-sm text-muted-foreground">
                      Auf diesem Server ist keine Discord-Anwendung eingerichtet.
                    </span>
                  )}
                </div>
              </>
            )}
          </dd>
        </dl>
      </Card>

      <h2 className="px-5 sm:px-6">Was du jetzt kannst</h2>
      <p className="flex flex-wrap gap-3 px-5 sm:px-6">
        <Link
          className={buttonVariants({
            variant: user.emailVerifiedAt && discord ? 'default' : 'secondary',
          })}
          href="/apply"
        >
          Bewerben
        </Link>
        <Link className={buttonVariants({ variant: 'secondary' })} href="/status">
          Mein Status
        </Link>
        {isStaff ? (
          <Link className={buttonVariants({ variant: 'secondary' })} href="/admin">
            Team-Bereich
          </Link>
        ) : null}
        <Link className={buttonVariants({ variant: 'secondary' })} href="/auth/logout">
          Abmelden
        </Link>
      </p>

      {!user.emailVerifiedAt || !discord ? (
        <p className="px-5 text-sm text-muted-foreground sm:px-6">
          Für eine Bewerbung brauchst du beides: eine bestätigte Adresse und ein
          verknüpftes Discord-Konto. Erst dann ist die Bewerbung einem Discord-Konto
          zuordenbar — und nur so kann der Spielserver sie beim Verbinden prüfen.
        </p>
      ) : null}
    </>
  );
}

const term = 'mt-4 text-xs uppercase tracking-[0.06em] text-muted-foreground';

const value = 'mt-1.5 mb-0';
