'use client';

import { useActionState } from 'react';
import Link from 'next/link';

import { cn } from '@/lib/utils';
import { Alert, Button, Input } from '@/components/ui';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import {
  Field,
  FieldDescription,
  FieldGroup,
  FieldLabel,
} from '@/components/ui/field';
import type { AuthState } from '@/lib/account-actions';

type Action = (state: AuthState, form: FormData) => Promise<AuthState>;

/**
 * One form, two pages.
 *
 * /login and /register are the same three fields, so they are the same component.
 * What differs is the submit label and whether the password is asked for twice —
 * a repeat field on a sign-in form is noise, and on a registration form it is the
 * only thing standing between a typo and a password nobody can recover.
 *
 * The structure is the shadcn login-01 block; the wiring (action, validation,
 * the repeat field) is project-specific. Both /login and /register use this
 * same component, so changing the look is a one-file change.
 */
export function LoginForm({
  className,
  action,
  mode,
}: {
  className?: string;
  action: Action;
  mode: 'login' | 'register';
}) {
  const [state, formAction, pending] = useActionState(action, undefined);

  const isRegister = mode === 'register';
  const title = isRegister ? 'Konto anlegen' : 'Anmelden';
  const submitLabel = isRegister ? 'Konto anlegen' : 'Anmelden';
  const altHref = isRegister ? '/login' : '/register';
  const altText = isRegister ? 'Schon ein Konto?' : 'Noch kein Konto?';
  const altLink = isRegister ? 'Hier anmelden' : 'Hier registrieren';

  return (
    <div className={cn('flex flex-col gap-6', className)}>
      <Card>
        <CardHeader>
          <CardTitle>{title}</CardTitle>
        </CardHeader>
        <CardContent>
          {state?.error ? (
            <Alert variant="destructive" role="alert" className="mb-4">
              {state.error}
            </Alert>
          ) : null}

          <form action={formAction}>
            <FieldGroup>
              {isRegister ? (
                <Field>
                  <FieldLabel htmlFor="username">Anzeigename</FieldLabel>
                  <Input
                    id="username"
                    name="username"
                    type="text"
                    autoComplete="username"
                    required
                    minLength={3}
                    maxLength={32}
                    pattern="[A-Za-z0-9](?:[A-Za-z0-9_\-]{1,30}[A-Za-z0-9])?"
                    placeholder="z.B. lilloco"
                  />
                </Field>
              ) : null}

              <Field>
                <FieldLabel htmlFor="email">E-Mail-Adresse</FieldLabel>
                <Input
                  id="email"
                  name="email"
                  type="email"
                  autoComplete="email"
                  required
                  maxLength={254}
                />
              </Field>

              <Field>
                <FieldLabel htmlFor="password">Passwort</FieldLabel>
                <Input
                  id="password"
                  name="password"
                  type="password"
                  autoComplete={isRegister ? 'new-password' : 'current-password'}
                  required
                  minLength={10}
                  maxLength={200}
                />
              </Field>

              {isRegister ? (
                <Field>
                  <FieldLabel htmlFor="password_repeat">
                    Passwort wiederholen
                  </FieldLabel>
                  <Input
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

              <Field>
                <Button type="submit" disabled={pending}>
                  {pending ? 'Einen Moment …' : submitLabel}
                </Button>
                <FieldDescription className="text-center">
                  {altText} <Link href={altHref}>{altLink}</Link>
                </FieldDescription>
              </Field>
            </FieldGroup>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
