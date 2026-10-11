import Link from 'next/link';

import { currentSession } from '@/lib/auth';
import { loginMode } from '@/lib/config';

const ERRORS: Record<string, string> = {
  'login-failed':
    'Die Anmeldung über Discord wurde nicht abgeschlossen. Bitte versuch es noch einmal.',
  'login-unavailable':
    'Die Anmeldung ist hier noch nicht eingerichtet. Zuerst muss eine Discord-Application angelegt werden.',
  'dev-auth-not-configured':
    'Die Entwicklungsanmeldung ist aktiv, aber DEV_DISCORD_ID ist keine gültige Discord-ID.',
};

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const [session, params] = await Promise.all([currentSession(), searchParams]);
  const mode = loginMode();
  const error = params.error ? ERRORS[params.error] : undefined;

  return (
    <>
      <h1>Nifty Life 2.0</h1>
      <p className="lede">
        Ein Roleplay-Server fürs Wochenende. Ein Charakter pro Person, offene Jobs
        für jeden, und alles, was du dir aufbaust, bleibt genau so liegen.
      </p>

      {error ? <div className="notice error">{error}</div> : null}

      <div className="card">
        {session ? (
          <>
            <p>
              Angemeldet als <strong>{session.username}</strong>{' '}
              <span className="muted small">({session.discordId})</span>
            </p>
            <p className="small muted">
              Diese Discord-ID ist deine Identität auf dem Server. Auf dieser Seite
              kann niemand eine Bewerbung freigeben — das macht ein Mensch.
            </p>
            <p style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
              <Link className="button" href="/apply">
                Bewerben
              </Link>
              <Link className="button secondary" href="/status">
                Mein Status
              </Link>
              <Link className="button secondary" href="/auth/logout">
                Abmelden
              </Link>
            </p>
          </>
        ) : (
          <>
            <p>
              Melde dich mit Discord an, um dich zu bewerben, deinen Status zu
              sehen und Peeper zu nutzen.
            </p>
            {mode === 'unavailable' ? (
              <p className="muted small">
                Die Anmeldung ist auf dieser Instanz noch nicht eingerichtet.
              </p>
            ) : (
              <Link className="button" href="/auth/login">
                {mode === 'dev' ? 'Anmelden (Entwicklung)' : 'Mit Discord anmelden'}
              </Link>
            )}
          </>
        )}
      </div>

      <h2>So läuft das</h2>
      <div className="card">
        <p className="small">
          <strong>Bewerben.</strong> Nenne Alter, Zeitzone und warum du hier spielen
          willst. Jede Bewerbung wird von einem Menschen gelesen und in Discord
          freigegeben oder abgelehnt.
        </p>
        <p className="small">
          <strong>Charakter verknüpfen.</strong> Peer wird von Charakteren
          geschrieben, nicht von Konten. Du erzeugst im Spiel einen Code, gibst ihn
          hier ein, und der Server bestätigt die Verknüpfung. Die Seite kann das
          nicht selbst bestätigen — das ist Absicht.
        </p>
        <p className="small">
          <strong>Freitag bis Sonntag.</strong> Der Server öffnet Freitag um 19:00
          und schließt Sonntag um 22:00. Geld, Immobilien und Verlauf bleiben
          dazwischen erhalten.
        </p>
      </div>
    </>
  );
}