'use client';

import { useActionState } from 'react';

import { Button, Notice } from '@/components/ui';
import { resendConfirmationAction, type AuthState } from '@/lib/account-actions';

/** "Schick mir den Link nochmal." Its own button because the form has no fields. */
export default function ResendButton() {
  const [state, formAction, pending] = useActionState(resendConfirmationAction, undefined);

  return (
    <form action={formAction}>
      {state?.error ? (
        <Notice tone="error" role="alert">
          {state.error}
        </Notice>
      ) : null}
      {state?.ok ? <Notice tone="ok">{state.ok}</Notice> : null}
      <Button variant="secondary" type="submit" disabled={pending}>
        {pending ? 'Einen Moment …' : 'Neuen Bestätigungslink schicken'}
      </Button>
    </form>
  );
}