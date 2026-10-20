import * as React from 'react';
import { Button, cn } from '@nifty/ui';
import { lua, type InventoryItem, type NearbyPlayer } from './contract';

/** How long the "An X gegeben." note stays up. Matches the vanilla panel. */
const NOTE_MS = 1500;

export interface TargetPickerProps {
  item: InventoryItem;
  /**
   * Carried for context only and deliberately NOT rendered: Lua rebuilds the
   * give payload from its own `giveMode` latch, so a number on screen here would
   * be a second, competing source of truth about how many are moving.
   */
  quantity: number;
  targets: NearbyPlayer[];
  onDismiss: () => void;
}

/**
 * "An wen:" — pick a recipient for the item currently latched in Lua's
 * `giveMode`.
 *
 * TWO THINGS THE VANILLA PANEL GOT WRONG HERE
 *
 * 1. ESC was checked against `.inv__menu, .inv__picker` but not
 *    `.inv__target-picker`, so ESC closed the entire inventory with the give
 *    flow half-open — and `giveMode` stayed latched on the client, so the next
 *    `confirmGive` anywhere in the session would fire against a stale row. The
 *    unmount effect below is the real fix: whenever this component goes away
 *    without a completed give, Lua is told to clear the latch.
 * 2. The target list is a snapshot from `enterGiveMode`. `refreshTargets` is
 *    registered on the Lua side and has never been called, so somebody who walks
 *    out of range in the two seconds the picker is open is still listed at their
 *    old distance. Wiring it up is a one-liner in `onOpen` and needs no Lua
 *    change; it is left out here so this stays a port.
 *
 * `exitGiveMode` is idempotent — Lua assigns `giveMode = nil` unconditionally —
 * so calling it on unmount after a confirmed give costs one no-op request.
 */
export function TargetPicker(props: TargetPickerProps) {
  const { item, quantity, targets, onDismiss } = props;
  const [note, setNote] = React.useState<string | null>(null);
  const timer = React.useRef<number | null>(null);

  React.useEffect(
    () => () => {
      if (timer.current !== null) window.clearTimeout(timer.current);
      void lua.exitGiveMode();
    },
    [],
  );

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

  const pick = React.useCallback(
    async (target: NearbyPlayer) => {
      const res = await lua.confirmGive({ targetSrc: target.src });

      // Transport failure (timeout, non-OK status): leave the picker up. The
      // request may well have reached Lua, and pretending the give is finished
      // would strand the latch with no visible reason.
      if (!res.ok) return;

      // Lua's `ok` here means "dispatched", not "delivered": the authoritative
      // answer arrives on `nifty:client:inventoryGive`, which no client in the
      // repo listens for. The note is optimistic by necessity, exactly as the
      // vanilla panel's was.
      if (res.value.ok !== true) {
        onDismiss();
        return;
      }

      setNote(`An ${target.name} gegeben.`);
      timer.current = window.setTimeout(onDismiss, NOTE_MS);
    },
    [onDismiss],
  );

  const title = (
    <div className="rounded-[var(--radius-panel)] border border-[color:var(--color-foreground)]/18 bg-[var(--color-card)]/94 px-4 py-3 text-sm font-semibold tracking-[0.04em] text-[var(--color-amber)]">
      An wen: {item.name || item.code}
    </div>
  );

  if (note !== null) {
    return (
      <div className="fixed inset-0 z-[60] flex items-start justify-center bg-black/65 pt-10">
        <div className="w-[min(420px,100%)] rounded-[var(--radius-panel)] border border-[var(--color-amber)]/40 bg-[var(--color-card)]/92 px-4 py-3.5 text-center text-[var(--color-amber)]">
          {note}
        </div>
      </div>
    );
  }

  return (
    <div
      className="fixed inset-0 z-[60] flex items-start justify-center bg-black/65 pt-10"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onDismiss();
      }}
    >
      <div className="flex w-[min(420px,100%)] flex-col gap-3.5 text-[var(--color-foreground)]">
        {title}

        <div className="flex flex-col gap-1.5">
          {targets.length === 0 ? (
            <div className="rounded-[var(--radius-panel)] border border-[color:var(--color-foreground)]/12 bg-[var(--color-card)]/92 px-4 py-3.5 text-center text-sm">
              Keine Spieler in Reichweite.
            </div>
          ) : (
            targets.map((target) => (
              <button
                key={target.src}
                type="button"
                onClick={() => {
                  void pick(target);
                }}
                className={cn(
                  'flex items-center justify-between rounded-[var(--radius-panel)] border',
                  'border-[color:var(--color-foreground)]/12 bg-[var(--color-card)]/92 px-4 py-2.5',
                  'text-left transition-colors',
                  'hover:border-[var(--color-amber)] hover:bg-[var(--color-amber)]/10',
                )}
              >
                <span className="text-sm text-[var(--color-foreground)]">{target.name}</span>
                <span className="text-[11px] text-[var(--color-muted-foreground)]">
                  {target.distance.toFixed(1)} m
                </span>
              </button>
            ))
          )}
        </div>

        <div className="flex justify-center">
          <Button variant="outline" size="sm" onClick={onDismiss}>
            Abbrechen
          </Button>
        </div>
      </div>
    </div>
  );
}