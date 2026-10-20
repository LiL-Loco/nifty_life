import * as React from 'react';

/**
 * Arm a timeout that is always torn down.
 *
 * The old panels sprinkled bare `setTimeout` calls with no bookkeeping — three
 * in store.js alone (the toast timer, the purchase close, and the line-expiry
 * equivalent). Any of them can fire after the panel closed, into a component
 * that is no longer mounted. Every timer in this package goes through here, so
 * unmounting the panel cancels all of them at once.
 *
 * Returns the cleanup so it can be the return value of a `useEffect` directly.
 */
export function useTimerRunner() {
  const timers = React.useRef(new Set<number>());

  React.useEffect(() => {
    const pending = timers.current;
    return () => {
      for (const t of pending) window.clearTimeout(t);
      pending.clear();
    };
  }, []);

  return React.useCallback((fn: () => void, ms: number) => {
    const id = window.setTimeout(() => {
      timers.current.delete(id);
      fn();
    }, ms);
    timers.current.add(id);
    return () => {
      window.clearTimeout(id);
      timers.current.delete(id);
    };
  }, []);
}

/**
 * True while a text input has focus.
 *
 * Both old screens refused to navigate on Escape while an input was focused
 * (`if (tag === 'INPUT') { e.target.blur(); return; }`) — typing a name and
 * pressing Escape should not also close the whole wardrobe. React has no
 * `event.target` for a document-level listener that survives the re-render, so
 * this reads `document.activeElement` instead.
 */
export function isEditingText(target: EventTarget | null): target is HTMLInputElement {
  return target instanceof HTMLInputElement;
}