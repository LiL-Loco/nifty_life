'use client';

import { useActionState } from 'react';

import { Button, Card, Field, Label, Notice } from '@/components/ui';
import {
  publish,
  report,
  staffDelete,
  staffPublish,
  toggleLike,
  type ActionState,
} from './actions';

export function Composer({ disabled }: { disabled: boolean }) {
  const [state, action] = useActionState<ActionState, FormData>(publish, undefined);

  return (
    <Card>
      <form action={action}>
        {state?.error ? (
          <Notice tone="error" role="alert">
            {state.error}
          </Notice>
        ) : null}
        {state?.ok ? <Notice tone="ok">{state.ok}</Notice> : null}

        <Field>
          <Label htmlFor="body">Schreib etwas</Label>
          <textarea
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
          <Label htmlFor="place">Ort (optional)</Label>
          <input id="place" name="place" maxLength={64} disabled={disabled} />
        </Field>

        <Button type="submit" disabled={disabled}>
          Abschicken
        </Button>
      </form>
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
    <Card accent>
      <p className="mb-3 mt-0 text-sm text-muted">
        <strong className="text-accent">P&amp;R-Team</strong> · du schreibst als{' '}
        <strong>{name}</strong>
      </p>

      <form action={action}>
        {state?.error ? (
          <Notice tone="error" role="alert">
            {state.error}
          </Notice>
        ) : null}
        {state?.ok ? <Notice tone="ok">{state.ok}</Notice> : null}

        <Field>
          <Label htmlFor="staff_body">Ankündigung</Label>
          <textarea
            id="staff_body"
            name="body"
            maxLength={500}
            placeholder="Bis zu 500 Zeichen. Sichtbar für alle."
            required
          />
        </Field>

        <Field>
          <Label htmlFor="staff_place">Ort (optional)</Label>
          <input id="staff_place" name="place" maxLength={64} />
        </Field>

        <Button type="submit">Veröffentlichen</Button>
      </form>
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
      <summary className="cursor-pointer list-none text-sm text-muted">löschen</summary>

      <form action={action} className="mt-2">
        <input type="hidden" name="post" value={postId} />

        {state?.error ? (
          <Notice tone="error" role="alert">
            {state.error}
          </Notice>
        ) : null}
        {state?.ok ? <Notice tone="ok">{state.ok}</Notice> : null}

        <p className="mb-1.5 mt-0 text-sm text-muted">
          Beitrag von <strong>{authorName}</strong> ausblenden. Der Beitrag bleibt in
          der Datenbank — gelöscht wird nur die Sichtbarkeit.
        </p>

        <input
          name="reason"
          maxLength={255}
          placeholder="Grund (optional, wird gespeichert)"
          className="px-1.5 py-1 text-[0.8125rem]"
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
    <div className="mt-2.5 flex gap-4 text-[0.8125rem] text-muted">
      <form action={likeAction}>
        <input type="hidden" name="post" value={postId} />
        <input type="hidden" name="liked" value="0" />
        <Button variant="secondary" size="sm" type="submit" disabled={disabled}>
          Gefällt mir · {likeCount}
        </Button>
      </form>

      <form action={reportAction}>
        <input type="hidden" name="post" value={postId} />
        <select
          name="reason"
          defaultValue="spam"
          disabled={disabled}
          className="w-auto py-1 pr-1 text-[0.8125rem]"
        >
          <option value="spam"> Spam</option>
          <option value="harassment"> Belästigung</option>
          <option value="impersonation"> Identitätsmissbrauch</option>
          <option value="other"> Sonstiges</option>
        </select>
        <Button variant="secondary" size="sm" type="submit" disabled={disabled}>
          Melden
        </Button>
      </form>

      {reportState?.error ? (
        <span className="text-danger">{reportState.error}</span>
      ) : null}
      {reportState?.ok ? <span>{reportState.ok}</span> : null}
    </div>
  );
}