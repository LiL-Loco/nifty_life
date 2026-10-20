import * as React from 'react';
import { Button, cn } from '@nifty/ui';

/**
 * The three widgets both screens are built from.
 *
 * The vanilla version had `button()`, `separator()` and `input()` duplicated
 * across wardrobe.js and store.js — two copies of the same DOM assembly, which
 * is why the two screens drifted apart. They live here once now.
 */

/* --------------------------------------------------------------------- Row */

export interface RowProps {
  label: string;
  desc?: string | null;
  onClick: () => void;
  /** The trailing `›`. Back rows and confirm buttons do not have one. */
  chevron?: boolean;
  variant?: 'default' | 'primary' | 'danger';
  disabled?: boolean;
}

/**
 * A full-width list row: label, optional dim description, optional chevron.
 *
 * Built on the shared `Button`, but the pill/uppercase defaults are undone —
 * a shadcn pill button is a control, this is a menu entry, and the whole
 * `wc-btn` idiom the wardrobe and store both used is a full-width
 * left-aligned two-line row. `cn`/twMerge is what makes overriding them safe.
 */
export function Row({ label, desc, onClick, chevron = true, variant = 'default', disabled }: RowProps) {
  return (
    <Button
      variant={variant === 'danger' ? 'destructive' : 'ghost'}
      disabled={disabled}
      onClick={onClick}
      className={cn(
        'h-auto w-full items-start justify-start gap-3 whitespace-normal rounded-[var(--radius-panel)] px-4 py-3 text-left text-[14px] font-semibold normal-case tracking-normal hover:border-[var(--color-amber)] hover:bg-[var(--color-accent)]',
        variant === 'primary' && 'border-[var(--color-amber)] text-[var(--color-amber)] hover:brightness-110',
        variant === 'danger' && 'border-destructive',
      )}
    >
      <span className="min-w-0 flex-1">
        <span className="block font-semibold">{label}</span>
        {desc ? (
          <span className="mt-0.5 block text-[11px] font-normal text-[var(--color-muted-foreground)]">
            {desc}
          </span>
        ) : null}
      </span>
      {chevron ? (
        <span aria-hidden className="mt-0.5 shrink-0 text-[18px] text-[var(--color-muted-foreground)]">
          ›
        </span>
      ) : null}
    </Button>
  );
}

/* ----------------------------------------------------------------- Caption */

/**
 * Section heading AND empty-state line.
 *
 * Not a coincidence: `.wc-separator` was one class doing both jobs
 * (`separator('Outfits')` for headings, `el('div','wc-separator','Keine Stuecke.')`
 * for empties), so they are one component here too.
 */
export function Caption({ children }: { children: string }) {
  return (
    <div className="mx-2 mb-1 mt-3 text-[10px] font-semibold uppercase tracking-[0.18em] text-[var(--color-muted-foreground)]">
      {children}
    </div>
  );
}

/* --------------------------------------------------------------- TextField */

export const TextField = React.forwardRef<
  HTMLInputElement,
  React.InputHTMLAttributes<HTMLInputElement>
>(({ className, ...props }, ref) => (
  <input
    ref={ref}
    type="text"
    autoComplete="off"
    spellCheck={false}
    className={cn(
      'w-full rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-secondary)] px-3 py-2.5 text-[14px] text-[var(--color-foreground)] outline-none focus:border-[var(--color-amber)]',
      className,
    )}
    {...props}
  />
));
TextField.displayName = 'TextField';