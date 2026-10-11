import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { discordConfigured } from '@/lib/config';
import { linkedCharacter, pairingRequests } from '@/lib/identity';
import { Button, Card, Field, Label, Notice, buttonLinkClass } from '@/components/ui';
import { pair } from './actions';

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
        <h1 className="mt-0">Zuerst Discord verknüpfen</h1>
        <p>
          Die Verknüpfung bindet genau einen Charakter an dein Discord-Konto. Ohne
          dieses Konto gibt es nichts zu binden.
        </p>
        <p className="flex flex-wrap gap-3">
          {discordConfigured ? (
            <Link
              className={buttonLinkClass()}
              href="/auth/discord/connect?next=/peeper/pair"
            >
              Discord-Konto verknüpfen
            </Link>
          ) : null}
          <Link className={buttonLinkClass({ variant: 'secondary' })} href="/account">
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
      <h1>Charakter verknüpfen</h1>
      <p className="mb-8 text-muted">
        Peeper wird von Charakteren geschrieben. Die Verknüpfung bindet dein
        Discord-Konto an genau einen deiner Charaktere.
      </p>

      {params.error ? (
        <Notice tone="error" role="alert">
          Dieser Code ist nicht verwendbar.
        </Notice>
      ) : null}

      {params.sent ? (
        <Notice tone="ok">
          Anfrage gesendet. Der Spielserver bestätigt sie, solange die Welt offen
          ist - Freitag 19:00 bis Sonntag 22:00. Codes laufen nach 15 Minuten ab.
        </Notice>
      ) : null}

      {link ? (
        <Notice tone="ok">
          Bereits mit dem Charakter{' '}
          <span className="text-xs">{link.characterId}</span> verknüpft. Ein Konto, ein
          Charakter - für einen Wechsel bitte in Discord melden.
        </Notice>
      ) : (
        <Card>
          <ol className="ml-4 list-decimal pl-0.5 text-sm">
            <li>Verbinde dich mit dem Server.</li>
            <li>Führe im Spiel den Befehl zur Code-Erzeugung aus.</li>
            <li>Trage den Code unten ein.</li>
          </ol>

          <form action={pair}>
            <Field>
              <Label htmlFor="code">Verknüpfungscode</Label>
              <input id="code" name="code" maxLength={16} autoComplete="off" required />
            </Field>
            <Button type="submit">Anfrage senden</Button>
          </form>

          <p className="mb-0 mt-4 text-sm text-muted">
            Diese Seite reicht den Code ein und kann ihn nicht selbst bestätigen.
            Diese Bestätigung gehört dem Spielserver - deshalb besitzt der
            Datenbankzugang hier auf keiner Tabelle ein UPDATE-Recht. Er könnte
            sich sonst selbst mit jedem Charakter verknüpfen.
          </p>
        </Card>
      )}

      {requests.length > 0 ? (
        <>
          <h2>Aktuelle Anfragen</h2>
          <ul className="text-sm text-muted">
            {requests.map((row) => (
              <li key={row.id}>gesendet am {row.created_at}</li>
            ))}
          </ul>
        </>
      ) : null}
    </>
  );
}