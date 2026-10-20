import * as React from 'react';
import { cn } from '@nifty/ui';
import { money } from './contract';

export interface ItemTileProps {
  label: string;
  quantity: number;
  /** Already multiplied out to the row total. */
  weight: number;
  /** Set for items carried for someone else; rendered as a `(von X)` suffix. */
  giverName?: string;
  /** OUTFIT rows: shown amber-tinted, no context menu. */
  readOnly?: boolean;
  onContextMenu?: (e: React.MouseEvent<HTMLLIElement>) => void;
}

/**
 * One inventory cell.
 *
 * Presentational on purpose: the BACKPACK rows carry a real `id` and open a
 * menu, the OUTFIT rows are derived from `character.appearance` and have
 * neither, so the component takes primitives instead of pretending both are the
 * same shape with optional fields.
 */
export function ItemTile(props: ItemTileProps) {
  const { label, quantity, weight, giverName, readOnly, onContextMenu } = props;

  const name = giverName ? `${label} (von ${giverName})` : label;

  return (
    <li
      onContextMenu={onContextMenu}
      title={name}
      className={cn(
        'relative flex min-h-16 select-none flex-col items-center justify-center gap-0.5',
        'rounded border border-[var(--color-border)] bg-black/40 px-1.5 pb-2 pt-3',
        'text-center text-[11px] leading-tight text-[var(--color-foreground)]',
        'transition-colors',
        onContextMenu && 'cursor-pointer hover:border-[var(--color-amber)]',
        readOnly && 'border-[var(--color-amber)]/20 bg-[var(--color-amber)]/[0.06]',
      )}
    >
      {quantity > 1 ? (
        <span className="absolute left-1 top-0.5 text-[9px] text-[var(--color-muted-foreground)]">
          x{quantity}
        </span>
      ) : null}

      <span className="w-full truncate">{name}</span>

      <span className="text-[9px] text-[var(--color-muted-foreground)]">
        {money(weight)} kg
      </span>
    </li>
  );
}