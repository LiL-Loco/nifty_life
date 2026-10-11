import { redirect } from 'next/navigation';

import { currentSession } from '@/lib/auth';
import { linkedCharacter, pairingRequests } from '@/lib/identity';
import { pair } from './actions';

export default async function PairPage({
  searchParams,
}: {
  searchParams: Promise<{ sent?: string; error?: string }>;
}) {
  const [session, params] = await Promise.all([currentSession(), searchParams]);
  if (!session) redirect('/');

  const [link, requests] = await Promise.all([
    linkedCharacter(session.discordId),
    pairingRequests(session.discordId),
  ]);

  return (
    <>
      <h1>Link your character</h1>
      <p className="lede">
        Peeper posts belong to a character. Linking binds this Discord account to
        exactly one of yours.
      </p>

      {params.error ? <div className="notice error">That code is not usable.</div> : null}

      {params.sent ? (
        <div className="notice ok">
          Request sent. The game server confirms it while the world is open — Friday
          19:00 to Sunday 22:00. Codes expire after 15 minutes.
        </div>
      ) : null}

      {link ? (
        <div className="notice ok">
          Already linked to character <span className="small">{link.characterId}</span>.
          One character per account; ask in Discord to change it.
        </div>
      ) : (
        <div className="card">
          <ol className="small" style={{ paddingLeft: '1.1rem' }}>
            <li>Connect to the server.</li>
            <li>Run the pairing command in game to get a code.</li>
            <li>Type it below.</li>
          </ol>

          <form action={pair}>
            <div className="field">
              <label htmlFor="code">Pairing code</label>
              <input id="code" name="code" maxLength={16} autoComplete="off" required />
            </div>
            <button type="submit">Send request</button>
          </form>

          <p className="small muted" style={{ marginTop: '1rem' }}>
            This site submits the code and cannot confirm it. That confirmation belongs
            to the game server, which is why the site has no UPDATE privilege on any
            table — it could otherwise link itself to any character.
          </p>
        </div>
      )}

      {requests.length > 0 ? (
        <>
          <h2>Recent requests</h2>
          <ul className="small muted">
            {requests.map((row) => (
              <li key={row.id}>submitted {row.created_at}</li>
            ))}
          </ul>
        </>
      ) : null}
    </>
  );
}