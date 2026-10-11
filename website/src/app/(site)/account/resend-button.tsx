'use client';

import { useActionState } from 'react';

import { Alert, Button } from '@/components/ui';
import { resendConfirmationAction, type AuthState } from '@/lib/account-actions';

/** "Schick mir den Link nochmal." Its own button because the form has no fields. */
export default function ResendButton() {
  const [state, formAction, pending] = useActionState(resendConfirmationAction, undefined);

  return (
    <form action={formAction}>
      {state?.error ? (
        <Alert variant="destructive" role="alert">
          {state.error}
        </Alert>
      ) : null}
      {state?.ok ? <Alert>{state.ok}</Alert> : null}
      <Button variant="secondary" type="submit" disabled={pending}>
        {pending ? 'Einen Moment …' : 'Neuen Bestätigungslink schicken'}
      </Button>
    </form>
  );
}
