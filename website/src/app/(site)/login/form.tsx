'use client';

import { useActionState } from 'react';

import { Button, Field, Label, Notice } from '@/components/ui';
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
        <Notice tone="error" role="alert">
          {state.error}
        </Notice>
      ) : null}

      <Field>
        <Label htmlFor="email">E-Mail-Adresse</Label>
        <input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          required
          maxLength={254}
        />
      </Field>

      <Field>
        <Label htmlFor="password">Passwort</Label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete={showRepeat ? 'new-password' : 'current-password'}
          required
          minLength={10}
          maxLength={200}
        />
        {showRepeat ? (
          <p className="mt-1.5 mb-0 text-sm text-muted">
            Mindestens 10 Zeichen. Keine Regeln zu Zeichenarten — ein Satz ist ein
            gutes Passwort.
          </p>
        ) : null}
      </Field>

      {showRepeat ? (
        <Field>
          <Label htmlFor="password_repeat">Passwort wiederholen</Label>
          <input
            id="password_repeat"
            name="password_repeat"
            type="password"
            autoComplete="new-password"
            required
            minLength={10}
            maxLength={200}
          />
        </Field>
      ) : null}

      <Button type="submit" disabled={pending}>
        {pending ? 'Einen Moment …' : submitLabel}
      </Button>
    </form>
  );
}