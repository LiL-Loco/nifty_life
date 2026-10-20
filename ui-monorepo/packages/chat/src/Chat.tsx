import * as React from 'react';
import { createBridge, cn } from '@nifty/ui';

/**
 * Chat panel.
 *
 * WHY THIS ONE KEEPS ITS OWN TIMERS INSTEAD OF DERIVING THEM
 *
 * The old vanilla version appended a <div> per line and stashed a per-node
 * expiry timer on the element's dataset, trimming from the front as it went.
 * That is genuinely incremental DOM work and React would normally replace it
 * with a re-render on every push.
 *
 * It is left equivalent on purpose: the log is written at a fixed rate by
 * chat, and a re-render per line would put more work in than the old code did.
 * The entry list is the state, the timers are a ref, and only the visible
 * slice re-renders.
 */

/** The three actions nifty-chat's Lua side actually sends. See client/cl_chat.lua. */
type ChatAction =
  | { chatLine: { author: string; text: string } }
  | { chatSystem: { text: string } }
  | { chatInput: { open: boolean } };

const bridge = createBridge<Record<string, () => void>>({
  received: ['chatLine', 'chatSystem', 'chatInput'],
});

/** Milliseconds a line stays before it fades and is removed. */
const CHAT_LINE_MS = 12_000;
/** Hard cap on retained lines, so a long session cannot grow without bound. */
const CHAT_MAX_LINES = 80;
/** How long the fade-out runs before the entry is dropped. */
const CHAT_LEAVE_MS = 650;

type LineKind = 'player' | 'system';

interface Line {
  id: number;
  kind: LineKind;
  author: string;
  text: string;
}

let nextId = 0;

export function Chat() {
  const [lines, setLines] = React.useState<Line[]>([]);
  const [inputOpen, setInputOpen] = React.useState(false);
  const [draft, setDraft] = React.useState('');
  const timers = React.useRef(new Map<number, number>());
  const fieldRef = React.useRef<HTMLInputElement | null>(null);

  const dropLine = React.useCallback((id: number) => {
    const t = timers.current.get(id);
    if (t !== undefined) {
      window.clearTimeout(t);
      timers.current.delete(id);
    }
    setLines((prev) => prev.filter((l) => l.id !== id));
  }, []);

  const pushLine = React.useCallback(
    (kind: LineKind, author: string, text: string) => {
      const id = nextId++;
      setLines((prev) => {
        const next = [...prev, { id, kind, author, text }];
        // Trim from the front, but only after the entry is actually rendered —
        // dropping it here would unmount a node whose timer is still pending.
        while (next.length > CHAT_MAX_LINES) {
          const oldest = next.shift();
          if (oldest) dropLine(oldest.id);
        }
        return next;
      });

      const t = window.setTimeout(() => dropLine(id), CHAT_LINE_MS);
      timers.current.set(id, t);
    },
    [dropLine],
  );

  /* ---- Lua -> panel -------------------------------------------------- */

  React.useEffect(
    () =>
      bridge.on('chatLine', (d) => pushLine('player', d.author, d.text)),
    [pushLine],
  );

  React.useEffect(
    () => bridge.on('chatSystem', (d) => pushLine('system', '', d.text)),
    [pushLine],
  );

  React.useEffect(
    () =>
      bridge.on('chatInput', (d) => {
        setInputOpen(Boolean(d.open));
        setDraft('');
        if (d.open) {
          // Focus AFTER the input exists. The Lua side grants focus before it
          // pushes, so the field is mounted but unfocused on this tick; focusing
          // in the same effect is what makes typing land in the right place.
          window.requestAnimationFrame(() => fieldRef.current?.focus());
        }
      }),
    [],
  );

  /* ---- cleanup ------------------------------------------------------- */

  React.useEffect(() => {
    const pending = timers.current;
    return () => {
      for (const t of pending.values()) window.clearTimeout(t);
      pending.clear();
    };
  }, []);

  /* ---- submit -------------------------------------------------------- */

  const send = React.useCallback(() => {
    const text = draft.trim();
    void bridge.call('chatSend', { text });
    setDraft('');
  }, [draft]);

  const cancel = React.useCallback(() => {
    void bridge.call('chatCancel', {});
    setDraft('');
  }, []);

  const onKeyDown = React.useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        send();
      } else if (e.key === 'Escape') {
        e.preventDefault();
        cancel();
      }
    },
    [send, cancel],
  );

  return (
    <>
      <div className="pointer-events-none fixed inset-x-0 bottom-24 flex flex-col items-center gap-1 px-4">
        {lines.map((l) => (
          <div
            key={l.id}
            className={cn(
              'max-w-[min(42rem,90vw)] rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-1.5 text-sm shadow-sm',
              l.kind === 'system' &&
                'bg-[var(--color-secondary)] text-[var(--color-muted-foreground)]',
            )}
          >
            {l.kind === 'player' ? (
              <>
                <span className="mr-2 font-bold text-[var(--color-amber)]">
                  {l.author}
                </span>
                <span className="text-[var(--color-foreground)]">{l.text}</span>
              </>
            ) : (
              <span>{l.text}</span>
            )}
          </div>
        ))}
      </div>

      {inputOpen ? (
        <div className="fixed inset-x-0 bottom-6 flex justify-center px-4">
          <div className="flex w-[min(42rem,90vw)] items-center gap-2 rounded-[var(--radius-panel)] border-3 border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 shadow-lg">
            <span className="font-bold text-[var(--color-amber)]">/</span>
            <input
              ref={fieldRef}
              type="text"
              value={draft}
              maxLength={150}
              autoComplete="off"
              spellCheck={false}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={onKeyDown}
              placeholder="Nachricht — Enter zum Senden, Esc zum Abbrechen"
              className="w-full bg-transparent text-[var(--color-foreground)] outline-none placeholder:text-[var(--color-muted-foreground)]"
            />
          </div>
        </div>
      ) : null}
    </>
  );
}