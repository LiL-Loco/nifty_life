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
        <label htmlFor="age">Age</label>
        <input id="age" name="age" inputMode="numeric" maxLength={2} required />
        <p className="small muted" style={{ margin: '0.35rem 0 0' }}>
          The server is 18+. This is checked again by a human.
        </p>
      </div>

      <div className="field">
        <label htmlFor="timezone">Timezone</label>
        <input
          id="timezone"
          name="timezone"
          placeholder="Europe/Berlin"
          maxLength={64}
          required
        />
      </div>

      <div className="field">
        <label htmlFor="experience">What have you played before?</label>
        <textarea id="experience" name="experience" maxLength={2000} required />
      </div>

      <div className="field">
        <label htmlFor="motivation">Why here?</label>
        <textarea id="motivation" name="motivation" maxLength={2000} required />
        <p className="small muted" style={{ margin: '0.35rem 0 0' }}>
          Be honest. Nobody expects a polished essay.
        </p>
      </div>

      <button type="submit">Submit application</button>

      <p className="small muted" style={{ marginTop: '1rem' }}>
        This website cannot approve you, and it cannot edit an application after
        sending it. A person in Discord does that. See your{' '}
        <Link href="/status">status</Link> at any time.
      </p>
    </form>
  );
}