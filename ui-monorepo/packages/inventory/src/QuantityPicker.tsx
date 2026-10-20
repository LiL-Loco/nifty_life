import * as React from 'react';
import { Button, cn } from '@nifty/ui';
import type { InventoryItem } from './contract';

export interface QuantityPickerProps {
  item: InventoryItem;
  /** What the confirmed quantity is FOR. The picker itself does not care. */
  intentLabel: string;
  /** Starting value, already clamped into [min, item.quantity] by the parent. */
  initial: number;
  min: number;
  onConfirm: (quantity: number) => void;
  onCancel: () => void;
}

/**
 * "Wie viele?" — the numeric prompt a stackable item goes through before use,
 * give, drop or split.
 *
 * The old picker clamped on OK (`NaN` or `< min` → `min`, above the stack →
 * the whole stack). That clamp lives here rather than in the caller so every
 * intent gets it, including the split default of `quantity - 1`.
 *
 * One behavioural change: the vanilla panel's backdrop click and Escape both
 * closed the PICKER only, and its own Escape handler did not stop propagation,
 * so the document-level ESC handler in app.js could close the whole inventory in
 * the same keypress. `stopPropagation` here plus the parent ignoring Escape
 * while any modal is open makes "ESC unwinds one layer" true.
 */
export function QuantityPicker(props: QuantityPickerProps) {
  const { item, intentLabel, initial, min, onConfirm, onCancel } = props;

  const [value, setValue] = React.useState(String(initial));
  const inputRef = React.useRef<HTMLInputElement | null>(null);

  React.useEffect(() => {
    const node = inputRef.current;
    if (!node) return;
    node.focus();
    node.select();
  }, []);

  const commit = React.useCallback(() => {
    let v = parseInt(value, 10);
    if (Number.isNaN(v) || v < min) v = min;
    if (v > item.quantity) v = item.quantity;
    onConfirm(v);
  }, [value, min, item.quantity, onConfirm]);

  React.useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        onCancel();
      }
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onCancel]);

  return (
    <div
      className="fixed inset-0 z-[60] flex items-center justify-center bg-black/65"
      onMouseDown={(e) => {
        // Backdrop only: a drag that started inside the card must not dismiss.
        if (e.target === e.currentTarget) onCancel();
      }}
    >
      <div className="flex min-w-60 flex-col gap-3 rounded-[var(--radius-panel)] border border-[color:var(--color-foreground)]/15 bg-[var(--color-card)]/96 px-5 py-4 text-[var(--color-foreground)] shadow-[0_12px_32px_rgba(0,0,0,0.6)]">
        <div className="text-sm font-semibold tracking-[0.04em] text-[var(--color-amber)]">
          {item.name || item.code} (x{item.quantity})
        </div>

        <div className="text-xs text-[var(--color-muted-foreground)]">
          Wie viele? <span className="opacity-70">({intentLabel})</span>
        </div>

        <input
          ref={inputRef}
          type="number"
          inputMode="numeric"
          min={min}
          max={item.quantity}
          value={value}
          autoComplete="off"
          spellCheck={false}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              commit();
            }
          }}
          className={cn(
            'w-full rounded border border-[color:var(--color-foreground)]/18 bg-black/45',
            'px-3 py-2 text-center text-lg text-[var(--color-foreground)]',
            'font-sans outline-none transition-colors',
            'focus:border-[var(--color-amber)]',
            // Chromium renders its own spin buttons; in a game panel they are
            // three more pixels of chrome nobody asked for.
            '[appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none',
            '[&::-webkit-outer-spin-button]:appearance-none',
          )}
        />

        <div className="flex justify-end gap-2">
          <Button variant="outline" size="sm" onClick={onCancel}>
            Abbrechen
          </Button>
          <Button size="sm" onClick={commit}>
            OK
          </Button>
        </div>
      </div>
    </div>
  );
}