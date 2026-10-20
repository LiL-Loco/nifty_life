import * as React from 'react';
import { cn } from '@nifty/ui';
import type { InventoryItem } from './contract';

export type MenuAction = 'use' | 'give' | 'drop' | 'split';

export interface ItemMenuProps {
  item: InventoryItem;
  /** Cursor position in client coordinates. */
  x: number;
  y: number;
  onAction: (action: MenuAction) => void;
  onDismiss: () => void;
}

/**
 * The right-click menu on a BACKPACK tile.
 *
 * THE LEAK THIS REPLACES
 *
 * The vanilla panel appended this menu to `document.body` on every right-click
 * and registered its dismiss listeners on `document` from inside a
 * `setTimeout(…, 0)`. `dismissMenu` removed the `click` listener and never the
 * `keydown` one, so every right-click during a session left another live
 * keydown handler behind. Here the listeners are an effect with a cleanup and
 * the "outside click" is an overlay element — nothing to forget.
 *
 * The menu does not decide what an action MEANS. A stackable item opens the
 * quantity picker first, a single item fires immediately, and both of those are
 * the parent's business; `onAction` only reports which button was hit.
 */
export function ItemMenu(props: ItemMenuProps) {
  const { item, x, y, onAction, onDismiss } = props;
  const nodeRef = React.useRef<HTMLDivElement | null>(null);
  const [pos, setPos] = React.useState({ left: x, top: y });

  // Clamp to the viewport. The old menu was positioned at the raw cursor
  // coordinates, so right-clicking near the bottom-right corner opened a menu
  // that ran off screen with no way to reach its lower entries.
  React.useLayoutEffect(() => {
    const node = nodeRef.current;
    if (!node) return;
    const rect = node.getBoundingClientRect();
    const pad = 8;
    setPos({
      left: Math.max(pad, Math.min(x, window.innerWidth - rect.width - pad)),
      top: Math.max(pad, Math.min(y, window.innerHeight - rect.height - pad)),
    });
  }, [x, y]);

  React.useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        onDismiss();
      }
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onDismiss]);

  const stackable = item.quantity > 1;

  const entries: { action: MenuAction | 'cancel'; label: string; dim?: boolean }[] = [
    { action: 'use', label: stackable ? 'Benutzen...' : 'Benutzen' },
    { action: 'give', label: stackable ? 'Geben...' : 'Geben' },
    { action: 'drop', label: stackable ? 'Wegwerfen...' : 'Wegwerfen' },
  ];
  // Aufteilen only means something for a stack; a single-unit row has nothing
  // to split.
  if (stackable) entries.push({ action: 'split', label: 'Aufteilen...' });
  entries.push({ action: 'cancel', label: 'Abbrechen', dim: true });

  return (
    <>
      <div
        className="fixed inset-0 z-40"
        onMouseDown={(e) => {
          e.preventDefault();
          onDismiss();
        }}
      />
      <div
        ref={nodeRef}
        role="menu"
        style={{ left: pos.left, top: pos.top }}
        className={cn(
          'fixed z-50 flex min-w-44 flex-col overflow-hidden rounded border',
          'border-[color:var(--color-foreground)]/20 bg-[var(--color-card)]/95 py-1',
          'text-xs text-[var(--color-foreground)] shadow-[0_12px_32px_rgba(0,0,0,0.6)]',
        )}
      >
        {entries.map((entry) => (
          <button
            key={entry.action}
            type="button"
            role="menuitem"
            onClick={() => {
              if (entry.action === 'cancel') onDismiss();
              else onAction(entry.action);
            }}
            className={cn(
              'px-3.5 py-2 text-left font-medium transition-colors',
              'border-b border-[color:var(--color-foreground)]/5 last:border-b-0',
              'hover:bg-[var(--color-amber)]/15 hover:text-[var(--color-amber)]',
              entry.dim && 'text-[11px] text-[var(--color-muted-foreground)]',
            )}
          >
            {entry.label}
          </button>
        ))}
      </div>
    </>
  );
}