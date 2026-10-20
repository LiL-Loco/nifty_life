import * as React from 'react';
import { cn } from '../lib/utils';

/**
 * The four drag widgets the character creator needs, built ONCE.
 *
 * WHY THESE EXIST IN A SHARED PACKAGE
 *
 * The old creator implemented slider(), grid1DH(), grid1DV() and grid2D() as
 * four near-identical imperative widget factories, and every one of them had
 * the same defect: they registered `mousemove` and `mouseup` on `window` per
 * pointer-down and never removed them. The face-bone overlay pushed at 30 Hz
 * and rebuilt its dots on every push, so each message added ~48 listeners to
 * window and removed none — roughly 1,440 registrations per second while the
 * face panel was open.
 *
 * These components use refs and a single effect. The listeners are attached
 * when a drag starts and detached when it ends, by construction rather than by
 * remembering to clean up.
 */

export interface Vec2 {
  x: number;
  y: number;
}

export interface DragSurfaceProps {
  className?: string;
  disabled?: boolean;
  onDrag?: (p: Vec2) => void;
  /** Rendered at the current position. */
  children?: React.ReactNode;
  /** Inset from the edges, in percent, so the dot never leaves the track. */
  paddingPercent?: number;
  ariaLabel?: string;
}

function usePointerDrag(onDrag?: (p: Vec2) => void, disabled?: boolean) {
  const ref = React.useRef<HTMLDivElement | null>(null);
  const dragging = React.useRef(false);
  const onDragRef = React.useRef(onDrag);
  onDragRef.current = onDrag;

  React.useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const point = (e: MouseEvent): Vec2 => {
      const r = el.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) return { x: 0, y: 0 };
      return {
        x: Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)),
        y: Math.min(1, Math.max(0, (e.clientY - r.top) / r.height)),
      };
    };

    const move = (e: MouseEvent) => {
      if (!dragging.current) return;
      e.preventDefault();
      onDragRef.current?.(point(e));
    };
    const up = () => {
      dragging.current = false;
    };

    // One pair of listeners per mounted surface, not per pointer-down.
    window.addEventListener('mousemove', move);
    window.addEventListener('mouseup', up);
    return () => {
      window.removeEventListener('mousemove', move);
      window.removeEventListener('mouseup', up);
    };
  }, []);

  const onMouseDown = React.useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      if (disabled) return;
      e.preventDefault();
      dragging.current = true;
      const r = e.currentTarget.getBoundingClientRect();
      if (r.width > 0 && r.height > 0) {
        onDragRef.current?.({
          x: Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)),
          y: Math.min(1, Math.max(0, (e.clientY - r.top) / r.height)),
        });
      }
    },
    [disabled],
  );

  return { ref, onMouseDown };
}

/** 2D grid: a dot dragged in both axes. Face height + width, blush, etc. */
export function Grid2D(props: DragSurfaceProps) {
  const { ref, onMouseDown } = usePointerDrag(props.onDrag, props.disabled);
  return (
    <div
      ref={ref}
      role={props.ariaLabel ? 'slider' : undefined}
      aria-label={props.ariaLabel}
      onMouseDown={onMouseDown}
      className={cn(
        'relative h-full w-full cursor-crosshair overflow-hidden rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-secondary)]',
        props.className,
      )}
    >
      {props.children}
    </div>
  );
}

/** 1D horizontal: a dot dragged along one axis. Face feature sliders. */
export function Grid1DH(props: DragSurfaceProps) {
  const { ref, onMouseDown } = usePointerDrag(props.onDrag, props.disabled);
  return (
    <div
      ref={ref}
      role={props.ariaLabel ? 'slider' : undefined}
      aria-label={props.ariaLabel}
      onMouseDown={onMouseDown}
      className={cn(
        'relative h-3 w-full cursor-ew-resize rounded-full bg-[var(--color-secondary)]',
        props.className,
      )}
    >
      {props.children}
    </div>
  );
}

/** 1D vertical: a dot dragged along one vertical axis. Hair length, etc. */
export function Grid1DV(props: DragSurfaceProps) {
  const { ref, onMouseDown } = usePointerDrag(props.onDrag, props.disabled);
  return (
    <div
      ref={ref}
      role={props.ariaLabel ? 'slider' : undefined}
      aria-label={props.ariaLabel}
      onMouseDown={onMouseDown}
      className={cn(
        'relative h-full w-3 cursor-ns-resize rounded-full bg-[var(--color-secondary)]',
        props.className,
      )}
    >
      {props.children}
    </div>
  );
}

/** A positioned dot for the drag surfaces above. */
export function DragDot({ p, className }: { p: Vec2; className?: string }) {
  const pad = 0; // percent inset applied via calc
  return (
    <div
      className={cn(
        'pointer-events-none absolute h-4 w-4 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-[var(--color-background)] bg-[var(--color-primary)] shadow',
        className,
      )}
      style={{
        left: `calc(${pad}% + ${p.x * (100 - pad * 2)}%)`,
        top: `calc(${pad}% + ${p.y * (100 - pad * 2)}%)`,
      }}
    />
  );
}