import * as React from 'react';
import { Button, cn } from '@nifty/ui';

/**
 * Panel chrome shared by the wardrobe and the store.
 *
 * The two screens used to be two IIFEs that each kept its own copy of
 * `toast()` and each attached a `closeBtn` listener to the SAME button in
 * index.html — whichever script loaded last won. One frame plus one header
 * component replaces both.
 *
 * The old toast lived 3200 ms and was replaced, never queued, by the next
 * message.
 */
export const TOAST_MS = 3200;

/** Monotonic so a re-shown identical message still remounts the node. */
let toastId = 0;

export interface PanelChrome {
  /** Fire the `closePanel` callback. Lua echoes `clothing:close` back. */
  close: () => void;
  toast: (message: string, isError?: boolean) => void;
}

const ChromeContext = React.createContext<PanelChrome | null>(null);

export function useChrome(): PanelChrome {
  const chrome = React.useContext(ChromeContext);
  if (!chrome) {
    throw new Error('nifty-clothing: useChrome() outside <PanelFrame>');
  }
  return chrome;
}

/**
 * The frame. Visibility is driven ONLY by the Lua pushes: `close()` asks Lua
 * to close and waits for the `clothing:close` broadcast, and the panel never
 * hides itself. The two must never disagree about who owns the cursor, so no
 * screen is allowed to set `open` itself.
 */
export function PanelFrame({
  open,
  onClose,
  children,
}: {
  open: boolean;
  onClose: () => void;
  children: React.ReactNode;
}) {
  const [toast, setToast] = React.useState<{ id: number; text: string; isError: boolean } | null>(
    null,
  );
  const timer = React.useRef<number | null>(null);

  const showToast = React.useCallback((text: string, isError = false) => {
    if (timer.current !== null) window.clearTimeout(timer.current);
    setToast({ id: ++toastId, text, isError });
    timer.current = window.setTimeout(() => {
      timer.current = null;
      setToast(null);
    }, TOAST_MS);
  }, []);

  React.useEffect(
    () => () => {
      if (timer.current !== null) window.clearTimeout(timer.current);
    },
    [],
  );

  const chrome = React.useMemo<PanelChrome>(
    () => ({ close: onClose, toast: showToast }),
    [onClose, showToast],
  );

  return (
    <ChromeContext.Provider value={chrome}>
      {open ? (
        <div className="fixed right-0 top-0 z-10 flex h-screen w-[420px] flex-col overflow-hidden rounded-none border-y-0 border-r-0 bg-[var(--color-background)]">
          {children}
        </div>
      ) : null}

      {toast ? (
        <div
          key={toast.id}
          role="status"
          className={cn(
            'pointer-events-none fixed bottom-6 left-1/2 z-[100] -translate-x-1/2 rounded-[var(--radius-panel)] border bg-[var(--color-background)] px-5 py-2.5 text-[13px]',
            toast.isError
              ? 'border-destructive text-destructive'
              : 'border-[var(--color-border)] text-[var(--color-foreground)]',
          )}
        >
          {toast.text}
        </div>
      ) : null}
    </ChromeContext.Provider>
  );
}

/**
 * The header. One component, two call sites — wardrobe and store — instead of
 * the single shared `#title` / `#subtitle` / `#closeBtn` nodes that both old
 * screens reached for by id and overwrote.
 */
export function PanelHeader({
  title,
  subtitle,
  aside,
  onClose,
}: {
  title: string;
  subtitle: string;
  /** The character's display name, wardrobe only. */
  aside?: string | null;
  onClose: () => void;
}) {
  return (
    <header className="relative flex flex-col gap-1 border-b border-[var(--color-border)] p-6 pb-2 pr-14">
      <div className="flex items-baseline justify-between gap-3">
        <h1 className="text-lg font-bold uppercase tracking-[0.12em] text-[var(--color-amber)]">
          {title}
        </h1>
        {aside ? (
          <span className="truncate text-[12px] text-[var(--color-muted-foreground)]">{aside}</span>
        ) : null}
      </div>
      <p className="text-sm text-[var(--color-muted-foreground)]">{subtitle}</p>
      <Button
        variant="ghost"
        size="icon"
        onClick={onClose}
        aria-label="Schließen"
        className="absolute right-4 top-4 h-7 w-7 text-lg font-normal normal-case tracking-normal"
      >
        ×
      </Button>
    </header>
  );
}