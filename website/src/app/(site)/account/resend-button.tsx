'use client';

import { useActionState } from 'react';

import { resendConfirmationAction, type AuthState } from '@/lib/account-actions';

/** "Schick mir den Link nochmal." Its own button because the form has no fields. */
export default function ResendButton() {
  const [state, formAction, pending] = useActionState(resendConfirmationAction, undefined);

  return (
    <form action={formAction}>
      {state?.error ? <div className="notice error">{state.error}</div> : null}
      {state?.ok ? <div className="notice ok">{state.ok}</div> : null}
      <button className="button secondary" type="submit" disabled={pending}>
        {pending ? 'Einen Moment …' : 'Neuen Bestätigungslink schicken'}
      </button>
    </form>
  );
}