'use client';

import { useActionState } from 'react';

import { decideAction } from '../actions';

/**
 * The decision form.
 *
 * Separate from the page because `useActionState` is a Client Component hook and
 * the page that reads the application is a Server Component. `tsc --noEmit`
 * passes on a file that mixes the two; only `next build` rejects it, which is
 * why this split exists rather than an inline form in page.tsx.
 */
export default function DecisionForm({ id, status }: { id: string; status: string }) {
  const [state, action] = useActionState(decideAction, undefined);

  // A decided application is shown, not re-decided. The record is the evidence:
  // re-readable for ever, never overwritable by a second opinion.
  if (status === 'approved' || status === 'rejected') {
    return <p className="small muted">Diese Bewerbung ist bereits entschieden.</p>;
  }

  return (
    <form action={action}>
      <input type="hidden" name="id" value={id} />

      {state && !state.ok ? <div className="notice error">{state.error}</div> : null}
      {state && state.ok ? <div className="notice">Gespeichert.</div> : null}

      <label className="small" style={{ display: 'block', marginBottom: '0.5rem' }}>
        Notiz für dich (optional, nicht für den Bewerber sichtbar)
        <textarea name="note" rows={2} maxLength={500} style={{ marginTop: '0.35rem' }} />
      </label>

      <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
        <button type="submit" name="status" value="approved">
          Freigeben
        </button>
        <button type="submit" name="status" value="under_review" className="secondary">
          In Prüfung
        </button>
        <button type="submit" name="status" value="rejected" className="secondary">
          Ablehnen
        </button>
      </div>
    </form>
  );
}