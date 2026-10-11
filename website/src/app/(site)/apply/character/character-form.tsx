'use client';

import { useActionState } from 'react';

import { Alert, Button, Card, CardContent, Input } from '@/components/ui';
import { Field, FieldGroup, FieldLabel } from '@/components/ui/field';
import { createCharacterAction, type CharacterState } from '@/lib/character-actions';

export function CharacterForm() {
  const [state, formAction, pending] = useActionState<CharacterState, FormData>(
    createCharacterAction,
    undefined,
  );

  return (
    <Card className="mx-5 sm:mx-6">
      <CardContent className="pt-0">
        <form action={formAction}>
          {state?.error ? (
            <Alert variant="destructive" role="alert" className="mb-4">
              {state.error}
            </Alert>
          ) : null}

          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="first_name">Vorname</FieldLabel>
              <Input
                id="first_name"
                name="first_name"
                type="text"
                required
                maxLength={64}
                autoFocus
              />
            </Field>

            <Field>
              <FieldLabel htmlFor="last_name">Nachname (optional)</FieldLabel>
              <Input id="last_name" name="last_name" type="text" maxLength={64} />
            </Field>

            <Field>
              <FieldLabel htmlFor="gender">Geschlecht</FieldLabel>
              <select
                id="gender"
                name="gender"
                required
                className="h-9 w-full rounded-md border border-input bg-transparent px-3 text-sm"
              >
                <option value="">Bitte wählen</option>
                <option value="male">männlich</option>
                <option value="female">weiblich</option>
                <option value="nonbinary">non-binär</option>
              </select>
            </Field>

            <Field>
              <FieldLabel htmlFor="date_of_birth">Geburtsdatum</FieldLabel>
              <Input
                id="date_of_birth"
                name="date_of_birth"
                type="date"
                required
                max="9999-12-31"
              />
            </Field>

            <Field>
              <FieldLabel htmlFor="birthplace">Geburtsort (optional)</FieldLabel>
              <Input
                id="birthplace"
                name="birthplace"
                type="text"
                maxLength={96}
              />
            </Field>

            <Field>
              <Button type="submit" disabled={pending}>
                {pending ? 'Einen Moment …' : 'Charakter anlegen'}
              </Button>
            </Field>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  );
}
