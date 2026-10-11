'use client';

import { useActionState } from 'react';

import { Alert, Button, Input, Label } from '@/components/ui';
import type { AuthState } from '@/lib/account-actions';

type Action = (state: AuthState, form: FormData) => Promise<AuthState>;

/**
 * One form, two pages.
 *
 * /login and /register are the same three fields, so they are the same component.
 * What differs is the submit label and whether the password is asked for twice —
 * a repeat field on a sign-in form is noise, and on a registration form it is the
 * only thing standing between a typo and a password nobody can recover.
 */
export default function AuthForm({
  action,
  submitLabel,
  showRepeat = false,
}: {
  action: Action;
  submitLabel: string;
  showRepeat?: boolean;
}) {
  const [state, formAction, pending] = useActionState(action, undefined);

  return (
    <form action={formAction}>
      {state?.error ? (
        <Alert variant="destructive" role="alert">
          {state.error}
        </Alert>
      ) : null}

      <div className="mb-4">
        <Label htmlFor="email" className="mb-1 block text-muted-foreground">
          E-Mail-Adresse
        </Label>
        <Input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          required
          maxLength={254}
        />
      </div>

      <div className="mb-4">
        <Label htmlFor="password" className="mb-1 block text-muted-foreground">
          Passwort
        </Label>
        <Input
          id="password"
          name="password"
          type="password"
          autoComplete={showRepeat ? 'new-password' : 'current-password'}
          required
          minLength={10}
          maxLength={200}
        />
        {showRepeat ? (
          <p className="mt-1.5 text-sm text-muted-foreground">
            Mindestens 10 Zeichen. Keine Regeln zu Zeichenarten — ein Satz ist ein
            gutes Passwort.
          </p>
        ) : null}
      </div>

      {showRepeat ? (
        <div className="mb-4">
          <Label
            htmlFor="password_repeat"
            className="mb-1 block text-muted-foreground"
          >
            Passwort wiederholen
          </Label>
          <Input
            id="password_repeat"
            name="password_repeat"
            type="password"
            autoComplete="new-password"
            required
            minLength={10}
            maxLength={200}
          />
        </div>
      ) : null}

      <Button type="submit" disabled={pending}>
        {pending ? 'Einen Moment …' : submitLabel}
      </Button>
    </form>
  );
}
