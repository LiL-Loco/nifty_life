'use client';

import { useActionState } from 'react';

import { Button, Notice } from '@/components/ui';
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
    return <p className="text-sm text-muted">Diese Bewerbung ist bereits entschieden.</p>;
  }

  return (
    <form action={action}>
      <input type="hidden" name="id" value={id} />

      {state && !state.ok ? (
        <Notice tone="error" role="alert">
          {state.error}
        </Notice>
      ) : null}
      {state && state.ok ? <Notice>Liegt gespeichert vor.</Notice> : null}

      <label className="mb-2 block text-sm text-muted">
        Notiz für dich (optional, nicht für den Bewerber sichtbar)
        <textarea name="note" rows={2} maxLength={500} className="mt-1.5" />
      </label>

      <div className="flex flex-wrap gap-3">
        <Button type="submit" name="status" value="approved">
          Freigeben
        </Button>
        <Button type="submit" name="status" value="under_review" variant="secondary">
          In Prüfung
        </Button>
        <Button type="submit" name="status" value="rejected" variant="secondary">
          Ablehnen
        </Button>
      </div>
    </form>
  );
}