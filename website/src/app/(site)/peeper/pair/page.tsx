import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { discordConfigured } from '@/lib/config';
import { linkedCharacter, pairingRequests } from '@/lib/identity';
import {
  Alert,
  Button,
  Card,
  CardContent,
  Input,
  buttonVariants,
} from '@/components/ui';
import { Field, FieldGroup, FieldLabel } from '@/components/ui/field';
import { pair } from './actions';

const SUCCESS_CLASS = 'border-success/40 bg-success/10 text-success [&>svg]:text-success';

export default async function PairPage({
  searchParams,
}: {
  searchParams: Promise<{ sent?: string; error?: string }>;
}) {
  const [account, params] = await Promise.all([currentAccount(), searchParams]);
  if (!account) redirect('/login');

  // A pairing request is keyed on the Discord ID, because the game server proves
  // it against `web_links.discord_id`. With no Discord account there is nothing to
  // request a pairing FOR, so the page says which step is missing instead of
  // offering a form that would be rejected on submit.
  if (!account.discord) {
    return (
      <Card className="max-w-[32rem]">
        <h1>Zuerst Discord verknüpfen</h1>
        <p>
          Die Verknüpfung bindet genau einen Charakter an dein Discord-Konto. Ohne
          dieses Konto gibt es nichts zu binden.
        </p>
        <p className="flex flex-wrap gap-3">
          {discordConfigured ? (
            <a
              className={buttonVariants()}
              href="/auth/discord/connect?next=/peeper/pair"
            >
              Discord-Konto verknüpfen
            </a>
          ) : null}
          <Link className={buttonVariants({ variant: 'secondary' })} href="/account">
            Zur Kontoseite
          </Link>
        </p>
      </Card>
    );
  }

  const discordId = account.discord.discordId;

  const [link, requests] = await Promise.all([
    linkedCharacter(discordId),
    pairingRequests(discordId),
  ]);

  return (
    <>
      <h1 className="px-5 sm:px-6">Charakter verknüpfen</h1>
      <p className="mb-8 px-5 text-muted-foreground sm:px-6">
        Peeper wird von Charakteren geschrieben. Die Verknüpfung bindet dein
        Discord-Konto an genau einen deiner Charaktere.
      </p>

      {params.error ? (
        <Alert variant="destructive" role="alert">
          Dieser Code ist nicht verwendbar.
        </Alert>
      ) : null}

      {params.sent ? (
        <Alert className={SUCCESS_CLASS}>
          Anfrage gesendet. Der Spielserver bestätigt sie, solange die Welt offen
          ist — Freitag 19:00 bis Sonntag 22:00. Codes laufen nach 15 Minuten ab.
        </Alert>
      ) : null}

      {link ? (
        <Alert className={SUCCESS_CLASS}>
          Bereits mit dem Charakter{' '}
          <span className="text-xs">{link.characterId}</span> verknüpft. Ein Konto,
          ein Charakter — für einen Wechsel bitte in Discord melden.
        </Alert>
      ) : (
        <Card>
          <CardContent>
            <ol className="my-0 ml-4 list-decimal pl-0.5 text-sm">
              <li>Verbinde dich mit dem Server.</li>
              <li>Führe im Spiel den Befehl zur Code-Erzeugung aus.</li>
              <li>Trage den Code unten ein.</li>
            </ol>

            <form action={pair}>
              <FieldGroup>
                <Field>
                  <FieldLabel htmlFor="code">Verknüpfungscode</FieldLabel>
                  <Input id="code" name="code" maxLength={16} autoComplete="off" required />
                </Field>
                <Field>
                  <Button type="submit">Anfrage senden</Button>
                </Field>
              </FieldGroup>
            </form>

            <p className="mb-0 mt-4 text-sm text-muted-foreground">
              Diese Seite schickt den Code weiter, bestätigen muss ihn der
              Spielserver. Du siehst die Verknüpfung also erst, wenn du wieder
              im Spiel bist.
            </p>
          </CardContent>
        </Card>
      )}

      {requests.length > 0 ? (
        <>
          <h2>Aktuelle Anfragen</h2>
          <ul className="text-sm text-muted-foreground">
            {requests.map((row) => (
              <li key={row.id}>gesendet am {row.created_at}</li>
            ))}
          </ul>
        </>
      ) : null}
    </>
  );
}
