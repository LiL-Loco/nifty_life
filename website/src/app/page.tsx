import Link from 'next/link';

import { currentSession } from '@/lib/auth';
import { loginMode } from '@/lib/config';

const ERRORS: Record<string, string> = {
  'login-failed': 'Discord did not complete the sign-in. Please try again.',
  'login-unavailable':
    'Sign-in is not configured yet. The Discord application has to be created first.',
  'dev-auth-not-configured':
    'Development sign-in is enabled but DEV_DISCORD_ID is not a valid Discord ID.',
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
        A weekend roleplay server. One character per person, jobs open to anyone,
        and everything you build stays exactly where you left it.
      </p>

      {error ? <div className="notice error">{error}</div> : null}

      <div className="card">
        {session ? (
          <>
            <p>
              Signed in as <strong>{session.username}</strong>{' '}
              <span className="muted small">({session.discordId})</span>
            </p>
            <p className="small muted">
              This Discord account is the whitelist identity. Nothing here can approve
              an application — a person does that.
            </p>
            <p style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
              <Link className="button" href="/apply">
                Apply
              </Link>
              <Link className="button secondary" href="/status">
                My status
              </Link>
              <Link className="button secondary" href="/auth/logout">
                Sign out
              </Link>
            </p>
          </>
        ) : (
          <>
            <p>
              Sign in with Discord to apply, check your application status, and use
              Peeper.
            </p>
            {mode === 'unavailable' ? (
              <p className="muted small">
                Sign-in is not configured on this instance yet.
              </p>
            ) : (
              <Link className="button" href="/auth/login">
                {mode === 'dev' ? 'Sign in (development)' : 'Sign in with Discord'}
              </Link>
            )}
          </>
        )}
      </div>

      <h2>How this works</h2>
      <div className="card">
        <p className="small">
          <strong>Apply.</strong> Tell us your age, timezone and why you want to play.{' '}
          A human reads every application and approves or rejects it in Discord.
        </p>
        <p className="small">
          <strong>Link your character.</strong> Peeper is written by characters, not
          accounts. Generate a code in game, type it here, and the server proves the
          link. The site cannot confirm it on its own — that is deliberate.
        </p>
        <p className="small">
          <strong>Friday to Sunday.</strong> The server opens Friday 19:00 and closes
          Sunday 22:00. Money, property and history persist in between.
        </p>
      </div>
    </>
  );
}