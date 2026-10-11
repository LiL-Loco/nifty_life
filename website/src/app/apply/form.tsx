'use client';

import Link from 'next/link';
import { useActionState } from 'react';

import { submit, type ApplyState } from './actions';

export default function ApplicationForm() {
  const [state, action] = useActionState<ApplyState, FormData>(submit, undefined);

  return (
    <form action={action}>
      {state?.error ? <div className="notice error">{state.error}</div> : null}

      <div className="field">
        <label htmlFor="age">Alter</label>
        <input id="age" name="age" inputMode="numeric" maxLength={2} required />
        <p className="small muted" style={{ margin: '0.35rem 0 0' }}>
          Ab 18 Jahren. Das prüft danach noch einmal ein Mensch.
        </p>
      </div>

      <div className="field">
        <label htmlFor="timezone">Zeitzone</label>
        <input
          id="timezone"
          name="timezone"
          placeholder="Europe/Berlin"
          maxLength={64}
          required
        />
      </div>

      <div className="field">
        <label htmlFor="experience">Was hast du vorher gespielt?</label>
        <textarea id="experience" name="experience" maxLength={2000} required />
      </div>

      <div className="field">
        <label htmlFor="motivation">Warum hier?</label>
        <textarea id="motivation" name="motivation" maxLength={2000} required />
        <p className="small muted" style={{ margin: '0.35rem 0 0' }}>
          Sehr ehrlich. Niemand erwartet einen gepflegten Aufsatz.
        </p>
      </div>

      <button type="submit">Bewerbung abschicken</button>

      <p className="small muted" style={{ marginTop: '1rem' }}>
        Diese Website kann dich nicht freigeben und eine abgeschickte Bewerbung
        nicht nachträglich ändern. Das macht ein Mensch in Discord. Den{' '}
        <Link href="/status">Status</Link> kannst du jederzeit abrufen.
      </p>
    </form>
  );
}