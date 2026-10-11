import type { Metadata } from 'next';
import Link from 'next/link';

import { currentSession } from '@/lib/auth';
import { loginMode } from '@/lib/config';

export const metadata: Metadata = {
  title: 'Anmelden — Nifty Life 2.0',
};

const ERRORS: Record<string, string> = {
  'login-failed':
    'Die Anmeldung über Discord wurde nicht abgeschlossen. Bitte versuch es noch einmal.',
  'login-unavailable':
    'Die Anmeldung ist hier noch nicht eingerichtet. Zuerst muss eine Discord-Application angelegt werden.',
  'dev-auth-not-configured':
    'Die Entwicklungsanmeldung ist aktiv, aber DEV_DISCORD_ID ist keine gültige Discord-ID.',
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const [session, params] = await Promise.all([currentSession(), searchParams]);
  const mode = loginMode();
  const error = params.error ? ERRORS[params.error] : undefined;

  if (session) {
    return (
      <div className="card">
        <h1 style={{ marginTop: 0 }}>Angemeldet</h1>
        <p>
          Du bist als <strong>{session.username}</strong> angemeldet{' '}
          <span className="muted small">({session.discordId})</span>.
        </p>
        <p className="small muted">
          Diese Discord-ID ist deine Identität. Eine Freigabe auf dieser Website
          entscheidet immer ein Mensch.
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
      </div>
    );
  }

  return (
    <div className="card">
      <h1 style={{ marginTop: 0 }}>Anmelden</h1>

      {error ? <div className="notice error">{error}</div> : null}

      {mode === 'unavailable' ? (
        <>
          <p>Die Anmeldung ist auf dieser Instanz noch nicht eingerichtet.</p>
          <p className="small muted">
            Es braucht eine Discord-Application mit Client-ID und Secret. Ohne sie
            gibt es keine Anmeldung und damit auch keine Bewerbung.
          </p>
        </>
      ) : (
        <>
          <p>
            Melde dich mit Discord an, um dich zu bewerben, deinen Status zu sehen und
            P&amp;R zu nutzen.
          </p>
          <Link className="button" href="/auth/login">
            {mode === 'dev' ? 'Anmelden (Entwicklung)' : 'Mit Discord anmelden'}
          </Link>
        </>
      )}

      <p className="small muted" style={{ marginTop: '1.5rem' }}>
        <Link href="/">Zurück zur Startseite</Link>
      </p>
    </div>
  );
}