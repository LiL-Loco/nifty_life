'use client';

import { useActionState } from 'react';

import { Alert, Button, Card, CardContent, Input, Textarea } from '@/components/ui';
import { Field, FieldGroup, FieldLabel } from '@/components/ui/field';
import {
  publish,
  report,
  staffDelete,
  staffPublish,
  toggleLike,
  type ActionState,
} from './actions';

const SUCCESS_CLASS = 'border-success/40 bg-success/10 text-success [&>svg]:text-success';

export function Composer({ disabled }: { disabled: boolean }) {
  const [state, action] = useActionState<ActionState, FormData>(publish, undefined);

  return (
    <Card>
      <CardContent>
        <form action={action}>
          {state?.error ? (
            <Alert variant="destructive" role="alert" className="mb-4">
              {state.error}
            </Alert>
          ) : null}
          {state?.ok ? (
            <Alert className={`mb-4 ${SUCCESS_CLASS}`}>{state.ok}</Alert>
          ) : null}

          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="body">Schreib etwas</FieldLabel>
              <Textarea
                id="body"
                name="body"
                maxLength={500}
                disabled={disabled}
                placeholder={
                  disabled ? 'Verknüpfe zuerst deinen Charakter.' : 'Bis zu 500 Zeichen.'
                }
                required
              />
            </Field>

            <Field>
              <FieldLabel htmlFor="place">Ort (optional)</FieldLabel>
              <Input id="place" name="place" maxLength={64} disabled={disabled} />
            </Field>

            <Field>
              <Button type="submit" disabled={disabled}>
                Abschicken
              </Button>
            </Field>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  );
}

/**
 * The team composer.
 *
 * Same surface, different author. It needs no linked character, which is the
 * point: a moderator who has never played the game still posts here, and the
 * post is still attributable to their Discord account rather than to nobody.
 */
export function StaffComposer({ name }: { name: string }) {
  const [state, action] = useActionState<ActionState, FormData>(staffPublish, undefined);

  return (
    <Card className="border-primary">
      <CardContent>
        <p className="mb-3 text-sm text-muted-foreground">
          <strong className="text-primary">P&amp;R-Team</strong> · du schreibst als{' '}
          <strong>{name}</strong>
        </p>

        <form action={action}>
          {state?.error ? (
            <Alert variant="destructive" role="alert" className="mb-4">
              {state.error}
            </Alert>
          ) : null}
          {state?.ok ? (
            <Alert className={`mb-4 ${SUCCESS_CLASS}`}>{state.ok}</Alert>
          ) : null}

          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="staff_body">Ankündigung</FieldLabel>
              <Textarea
                id="staff_body"
                name="body"
                maxLength={500}
                placeholder="Bis zu 500 Zeichen. Sichtbar für alle."
                required
              />
            </Field>

            <Field>
              <FieldLabel htmlFor="staff_place">Ort (optional)</FieldLabel>
              <Input id="staff_place" name="place" maxLength={64} />
            </Field>

            <Field>
              <Button type="submit">Veröffentlichen</Button>
            </Field>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  );
}

/**
 * Soft-delete one post.
 *
 * `<details>` rather than a modal: deleting is destructive enough to want a
 * deliberate click, but not so heavy that it deserves a dialog. The reason field
 * lives here because this is the only moment the moderator is looking at the
 * post they are about to remove.
 */
export function DeletePost({ postId, authorName }: { postId: string; authorName: string }) {
  const [state, action] = useActionState<ActionState, FormData>(staffDelete, undefined);

  return (
    <details className="ml-auto">
      <summary className="cursor-pointer list-none text-sm text-muted-foreground">löschen</summary>

      <form action={action} className="mt-2">
        <input type="hidden" name="post" value={postId} />

        {state?.error ? (
          <Alert variant="destructive" role="alert" className="mb-2">
            {state.error}
          </Alert>
        ) : null}
        {state?.ok ? (
          <Alert className={`mb-2 ${SUCCESS_CLASS}`}>{state.ok}</Alert>
        ) : null}

        <p className="mb-1.5 text-sm text-muted-foreground">
          Beitrag von <strong>{authorName}</strong> ausblenden. Der Beitrag bleibt
          in der Datenbank — gelöscht wird nur die Sichtbarkeit.
        </p>

        <Input
          name="reason"
          maxLength={255}
          placeholder="Grund (optional, wird gespeichert)"
          className="h-8 text-sm"
        />
        <Button type="submit" variant="secondary" size="sm" className="mt-1.5">
          Löschen
        </Button>
      </form>
    </details>
  );
}

export function PostActions({
  postId,
  likeCount,
  disabled,
}: {
  postId: string;
  likeCount: number;
  disabled: boolean;
}) {
  const [, likeAction] = useActionState<ActionState, FormData>(toggleLike, undefined);
  const [reportState, reportAction] = useActionState<ActionState, FormData>(
    report,
    undefined,
  );

  return (
    <div className="mt-2.5 flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
      <form action={likeAction}>
        <input type="hidden" name="post" value={postId} />
        <input type="hidden" name="liked" value="0" />
        <Button variant="secondary" size="sm" type="submit" disabled={disabled}>
          Gefällt mir · {likeCount}
        </Button>
      </form>

      <form action={reportAction} className="flex items-center gap-1.5">
        <input type="hidden" name="post" value={postId} />
        <select
          name="reason"
          defaultValue="spam"
          disabled={disabled}
          className="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
        >
          <option value="spam">Spam</option>
          <option value="harassment">Belästigung</option>
          <option value="impersonation">Identitätsmissbrauch</option>
          <option value="other">Sonstiges</option>
        </select>
        <Button variant="secondary" size="sm" type="submit" disabled={disabled}>
          Melden
        </Button>
      </form>

      {reportState?.error ? (
        <span className="text-destructive">{reportState.error}</span>
      ) : null}
      {reportState?.ok ? <span>{reportState.ok}</span> : null}
    </div>
  );
}
