import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { discordConfigured } from '@/lib/config';
import { linkedCharacter, pairingRequests } from '@/lib/identity';
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
      <div className="card" style={{ maxWidth: '32rem' }}>
        <h1 style={{ marginTop: 0 }}>Zuerst Discord verknüpfen</h1>
        <p>
          Die Verknüpfung bindet genau einen Charakter an dein Discord-Konto. Ohne
          dieses Konto gibt es nichts zu binden.
        </p>
        <p style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
          {discordConfigured ? (
            <Link className="button" href="/auth/discord/connect?next=/peeper/pair">
              Discord-Konto verknüpfen
            </Link>
          ) : null}
          <Link className="button secondary" href="/account">
            Zur Kontoseite
          </Link>
        </p>
      </div>
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
      <p className="lede">
        Peeper wird von Charakteren geschrieben. Die Verknüpfung bindet dein
        Discord-Konto an genau einen deiner Charaktere.
      </p>

      {params.error ? (
        <div className="notice error">Dieser Code ist nicht verwendbar.</div>
      ) : null}

      {params.sent ? (
        <div className="notice ok">
          Anfrage gesendet. Der Spielserver bestätigt sie, solange die Welt offen
          ist - Freitag 19:00 bis Sonntag 22:00. Codes laufen nach 15 Minuten ab.
        </div>
      ) : null}

      {link ? (
        <div className="notice ok">
          Bereits mit dem Charakter{' '}
          <span className="small">{link.characterId}</span> verknüpft. Ein Konto, ein
          Charakter - für einen Wechsel bitte in Discord melden.
        </div>
      ) : (
        <div className="card">
          <ol className="small" style={{ paddingLeft: '1.1rem' }}>
            <li>Verbinde dich mit dem Server.</li>
            <li>Führe im Spiel den Befehl zur Code-Erzeugung aus.</li>
            <li>Trage den Code unten ein.</li>
          </ol>

          <form action={pair}>
            <div className="field">
              <label htmlFor="code">Verknüpfungscode</label>
              <input id="code" name="code" maxLength={16} autoComplete="off" required />
            </div>
            <button type="submit">Anfrage senden</button>
          </form>

          <p className="small muted" style={{ marginTop: '1rem' }}>
            Diese Seite reicht den Code ein und kann ihn nicht selbst bestätigen.
            Diese Bestätigung gehört dem Spielserver - deshalb besitzt der
            Datenbankzugang hier auf keiner Tabelle ein UPDATE-Recht. Er könnte
            sich sonst selbst mit jedem Charakter verknüpfen.
          </p>
        </div>
      )}

      {requests.length > 0 ? (
        <>
          <h2>Aktuelle Anfragen</h2>
          <ul className="small muted">
            {requests.map((row) => (
              <li key={row.id}>gesendet am {row.created_at}</li>
            ))}
          </ul>
        </>
      ) : null}
    </>
  );
}