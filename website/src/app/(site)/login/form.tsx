'use client';

import { useActionState } from 'react';

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
      {state?.error ? <div className="notice error">{state.error}</div> : null}

      <div className="field">
        <label htmlFor="email">E-Mail-Adresse</label>
        <input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          required
          maxLength={254}
        />
      </div>

      <div className="field">
        <label htmlFor="password">Passwort</label>
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
          <p className="small muted" style={{ margin: '0.35rem 0 0' }}>
            Mindestens 10 Zeichen. Keine Regeln zu Zeichenarten — ein Satz ist ein
            gutes Passwort.
          </p>
        ) : null}
      </div>

      {showRepeat ? (
        <div className="field">
          <label htmlFor="password_repeat">Passwort wiederholen</label>
          <input
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

      <button type="submit" disabled={pending}>
        {pending ? 'Einen Moment …' : submitLabel}
      </button>
    </form>
  );
}