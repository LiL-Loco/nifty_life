'use client';

import { useActionState } from 'react';

import { publish, report, staffDelete, staffPublish, toggleLike, type ActionState } from './actions';

export function Composer({ disabled }: { disabled: boolean }) {
  const [state, action] = useActionState<ActionState, FormData>(publish, undefined);

  return (
    <div className="card">
      <form action={action}>
        {state?.error ? <div className="notice error">{state.error}</div> : null}
        {state?.ok ? <div className="notice ok">{state.ok}</div> : null}

        <div className="field">
          <label htmlFor="body">Schreib etwas</label>
          <textarea
            id="body"
            name="body"
            maxLength={500}
            disabled={disabled}
            placeholder={
              disabled
                ? 'Verknüpfe zuerst deinen Charakter.'
                : 'Bis zu 500 Zeichen.'
            }
            required
          />
        </div>

        <div className="field">
          <label htmlFor="place">Ort (optional)</label>
          <input id="place" name="place" maxLength={64} disabled={disabled} />
        </div>

        <button type="submit" disabled={disabled}>
          Abschicken
        </button>
      </form>
    </div>
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
    <div className="card" style={{ borderColor: 'var(--accent)' }}>
      <p className="small muted" style={{ margin: '0 0 0.75rem' }}>
        <strong style={{ color: 'var(--accent)' }}>P&amp;R-Team</strong> · du schreibst
        als <strong>{name}</strong>
      </p>

      <form action={action}>
        {state?.error ? <div className="notice error">{state.error}</div> : null}
        {state?.ok ? <div className="notice ok">{state.ok}</div> : null}

        <div className="field">
          <label htmlFor="staff_body">Ankündigung</label>
          <textarea
            id="staff_body"
            name="body"
            maxLength={500}
            placeholder="Bis zu 500 Zeichen. Sichtbar für alle."
            required
          />
        </div>

        <div className="field">
          <label htmlFor="staff_place">Ort (optional)</label>
          <input id="staff_place" name="place" maxLength={64} />
        </div>

        <button type="submit">Veröffentlichen</button>
      </form>
    </div>
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
    <details style={{ marginLeft: 'auto' }}>
      <summary className="small muted" style={{ cursor: 'pointer', listStyle: 'none' }}>
        löschen
      </summary>

      <form action={action} style={{ marginTop: '0.5rem' }}>
        <input type="hidden" name="post" value={postId} />

        {state?.error ? <div className="notice error">{state.error}</div> : null}
        {state?.ok ? <div className="notice ok">{state.ok}</div> : null}

        <p className="small muted" style={{ margin: '0 0 0.4rem' }}>
          Beitrag von <strong>{authorName}</strong> ausblenden. Der Beitrag bleibt in
          der Datenbank — gelöscht wird nur die Sichtbarkeit.
        </p>

        <input
          name="reason"
          maxLength={255}
          placeholder="Grund (optional, wird gespeichert)"
          style={{ fontSize: '0.8125rem', padding: '0.25rem 0.4rem', width: '100%' }}
        />
        <button
          type="submit"
          className="secondary"
          style={{ marginTop: '0.4rem', padding: '0.25rem 0.6rem', fontSize: '0.8125rem' }}
        >
          Löschen
        </button>
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
    <div className="post-foot">
      <form action={likeAction}>
        <input type="hidden" name="post" value={postId} />
        <input type="hidden" name="liked" value="0" />
        <button
          className="secondary"
          type="submit"
          disabled={disabled}
          style={{ padding: '0.25rem 0.6rem', fontSize: '0.8125rem' }}
        >
          Gefällt mir · {likeCount}
        </button>
      </form>

      <form action={reportAction}>
        <input type="hidden" name="post" value={postId} />
        <select
          name="reason"
          defaultValue="spam"
          disabled={disabled}
          style={{ padding: '0.2rem', fontSize: '0.8125rem', width: 'auto' }}
        >
          <option value="spam"> Spam</option>
          <option value="harassment"> Belästigung</option>
          <option value="impersonation"> Identitätsmissbrauch</option>
          <option value="other"> Sonstiges</option>
        </select>
        <button
          className="secondary"
          type="submit"
          disabled={disabled}
          style={{ padding: '0.25rem 0.6rem', fontSize: '0.8125rem' }}
        >
          Melden
        </button>
      </form>

      {reportState?.error ? (
        <span style={{ color: 'var(--danger)' }}>{reportState.error}</span>
      ) : null}
      {reportState?.ok ? <span>{reportState.ok}</span> : null}
    </div>
  );
}