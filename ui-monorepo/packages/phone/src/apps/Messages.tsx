import * as React from 'react';
import {
  labelOf,
  onThread,
  send,
  type PhoneMessage,
  type PhoneThread,
} from '../contract';

/**
 * Messages: the thread list, and one conversation at a time.
 *
 * WHY A THREAD IS FETCHED SEPARATELY
 *
 * The open payload carries every thread's LAST message, because that is what the
 * list draws. Full histories come from `phoneOpenThread` when a conversation is
 * opened. Folding the histories into the open payload would mean opening the
 * phone reads the entire message history of a character who has played for a
 * month, every time, for a list that shows one line per conversation.
 *
 * WHY CLEARING IS PER SIDE
 *
 * `phoneClearThread` sets `cleared_by_recipient` for the reader. The other party
 * keeps everything: one player tidying up their inbox must not be able to delete
 * somebody else's history (ADR-0004 — the record is permanent), and the panel
 * offers it as a local action, not a global one.
 */
export function Messages({
  threads,
  limits,
}: {
  threads: PhoneThread[];
  limits: { MESSAGE_BODY: number; ALIAS: number; THREAD_PAGE: number };
}) {
  const [openNumber, setOpenNumber] = React.useState<string | null>(null);
  const [messages, setMessages] = React.useState<PhoneMessage[]>([]);
  const [draft, setDraft] = React.useState('');

  React.useEffect(
    () =>
      onThread((data) => {
        // A thread that arrives after the player has already left it is dropped.
        // Rendering it into the next conversation they open is worse than not
        // showing it, and the list re-fetches on open anyway.
        if (data.number !== openNumber) return;
        setMessages(data.messages ?? []);
      }),
    [openNumber],
  );

  /** Compose into a conversation from the dialer or the contact book. */
  React.useEffect(() => {
    const onCompose = (event: Event) => {
      const number = (event as CustomEvent<string>).detail;
      setOpenNumber(number);
      void send('phoneOpenThread', { number });
    };
    window.addEventListener('phone:compose', onCompose);
    return () => window.removeEventListener('phone:compose', onCompose);
  }, []);

  const open = (number: string) => {
    setOpenNumber(number);
    setMessages([]);
    void send('phoneOpenThread', { number, limit: limits.THREAD_PAGE });
  };

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    const body = draft.trim();
    if (body === '' || openNumber === null) return;

    void send('phoneSendMessage', { to: openNumber, body });
    setDraft('');
  };

  /* ---- one conversation ------------------------------------------------ */

  if (openNumber !== null) {
    const peer = threads.find((t) => t.number === openNumber);

    return (
      <div className="flex h-full flex-col">
        <div className="flex items-center justify-between border-b border-[var(--color-border)] px-3 py-2">
          <button
            type="button"
            onClick={() => {
              setOpenNumber(null);
              setMessages([]);
            }}
            className="text-xs text-[var(--color-primary)]"
          >
            ‹ Alle
          </button>
          <span className="truncate text-sm font-semibold">
            {peer ? labelOf(peer) : openNumber}
          </span>
          <button
            type="button"
            onClick={() => void send('phoneClearThread', { number: openNumber })}
            className="text-xs text-[var(--color-muted-foreground)]"
          >
            Leeren
          </button>
        </div>

        {/* Oldest first. The query asks for DESC because it has to LIMIT at the
            database end, and reversing here is what keeps a month of history from
            being fetched to show the last fifty. */}
        <div className="min-h-0 flex-1 overflow-y-auto px-3 py-2">
          {messages.length === 0 ? (
            <p className="py-8 text-center text-xs text-[var(--color-muted-foreground)]">
              Keine Nachrichten.
            </p>
          ) : (
            <ul className="flex flex-col gap-1.5">
              {[...messages].reverse().map((m) => {
                const mine = m.recipient_id === peer?.number;
                return (
                  <li
                    key={m.id}
                    className={[
                      'max-w-[85%] rounded-[var(--radius-panel)] px-2.5 py-1.5 text-sm',
                      mine
                        ? 'self-end bg-[var(--color-primary)] text-[var(--color-primary-foreground)]'
                        : 'self-start bg-[var(--color-secondary)] text-[var(--color-secondary-foreground)]',
                    ].join(' ')}
                  >
                    {m.body}
                  </li>
                );
              })}
            </ul>
          )}
        </div>

        <form onSubmit={submit} className="flex gap-1.5 border-t border-[var(--color-border)] p-2">
          <input
            type="text"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            // Escape inside the field belongs to the field; the panel-level
            // handler skips it and this one just blurs, which is what a chat box
            // is expected to do rather than closing the whole phone.
            onKeyDown={(e) => {
              if (e.key === 'Escape') (e.target as HTMLInputElement).blur();
            }}
            maxLength={limits.MESSAGE_BODY}
            placeholder="Nachricht…"
            autoComplete="off"
            spellCheck={false}
            className="min-w-0 flex-1 rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-background)] px-2.5 py-2 text-sm outline-none placeholder:text-[var(--color-muted-foreground)]"
          />
          <button
            type="submit"
            disabled={draft.trim() === ''}
            className="rounded-[var(--radius-panel)] bg-[var(--color-primary)] px-4 text-xs font-bold text-[var(--color-primary-foreground)] disabled:opacity-40"
          >
            Senden
          </button>
        </form>
      </div>
    );
  }

  /* ---- the list -------------------------------------------------------- */

  return (
    <div className="h-full overflow-y-auto">
      {threads.length === 0 ? (
        <p className="px-4 py-8 text-center text-xs text-[var(--color-muted-foreground)]">
          Keine Unterhaltungen.
        </p>
      ) : (
        <ul>
          {threads.map((t) => (
            <li key={t.number}>
              <button
                type="button"
                onClick={() => open(t.number)}
                className="flex w-full items-center gap-2 border-b border-[var(--color-border)] px-3 py-2.5 text-left hover:bg-[var(--color-accent)]"
              >
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-semibold">{labelOf(t)}</span>
                  <span className="block truncate text-xs text-[var(--color-muted-foreground)]">
                    {t.last_body}
                  </span>
                </span>
                {t.unread && t.unread > 0 ? (
                  <span className="min-w-[20px] shrink-0 rounded-full bg-[var(--color-primary)] px-1.5 text-center text-[10px] font-bold text-[var(--color-primary-foreground)]">
                    {t.unread}
                  </span>
                ) : null}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}