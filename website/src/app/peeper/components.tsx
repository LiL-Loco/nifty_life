'use client';

import { useActionState } from 'react';

import { publish, report, toggleLike, type ActionState } from './actions';

export function Composer({ disabled }: { disabled: boolean }) {
  const [state, action] = useActionState<ActionState, FormData>(publish, undefined);

  return (
    <div className="card">
      <form action={action}>
        {state?.error ? <div className="notice error">{state.error}</div> : null}
        {state?.ok ? <div className="notice ok">{state.ok}</div> : null}

        <div className="field">
          <label htmlFor="body">Write something</label>
          <textarea
            id="body"
            name="body"
            maxLength={500}
            disabled={disabled}
            placeholder={disabled ? 'Link your character to post.' : 'Up to 500 characters.'}
            required
          />
        </div>

        <div className="field">
          <label htmlFor="place">Place (optional)</label>
          <input id="place" name="place" maxLength={64} disabled={disabled} />
        </div>

        <button type="submit" disabled={disabled}>
          Post
        </button>
      </form>
    </div>
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
  const [reportState, reportAction] = useActionState<ActionState, FormData>(report, undefined);

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
          Like · {likeCount}
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
          <option value="spam">spam</option>
          <option value="harassment">harassment</option>
          <option value="impersonation">impersonation</option>
          <option value="other">other</option>
        </select>
        <button
          className="secondary"
          type="submit"
          disabled={disabled}
          style={{ padding: '0.25rem 0.6rem', fontSize: '0.8125rem' }}
        >
          Report
        </button>
      </form>

      {reportState?.error ? (
        <span style={{ color: 'var(--danger)' }}>{reportState.error}</span>
      ) : null}
      {reportState?.ok ? <span>{reportState.ok}</span> : null}
    </div>
  );
}