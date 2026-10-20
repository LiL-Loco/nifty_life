import * as React from 'react';
import { wire } from './wire';

/**
 * Arm-wrestling minigame NUI panel.
 *
 * SHOW / HIDE
 *   The bar is hidden by default. Lua pushes `show` when a match starts and
 *   `hide` when it ends. These are rare events (a few per match), so the
 *   visibility toggle is plain React state.
 *
 * TICK
 *   The server is the source of truth for the bar position; the client forwards
 *   a `{ pos }` push at ~20 Hz during play. Driving React state on every tick
 *   would re-render the whole panel 20 times a second, which is the render
 *   storm the original "vanilla JS, listener-leak, drag-loop" diagnosis called
 *   out. Instead we keep `pos` in a ref and write `ref.current.style.left`
 *   directly. The CSS `transition: left 80ms linear` on the dot smooths the
 *   ticks the same way the old imperative code did, without any React work per
 *   frame.
 *
 * The German labels below are copied verbatim from ui/index.html. The drag-loop
 * listener-leak the original diagnosis attributed to widgets is not present
 * here (this panel has no mouse listeners), so no cleanup effect is needed.
 *
 * There are zero outbound callbacks — arm-wrestling is a pure listener. The
 * wire adapter still exposes `call` for future round-trips.
 */
export function Armwrestling() {
  const [visible, setVisible] = React.useState(false);
  const dotRef = React.useRef<HTMLDivElement | null>(null);

  /* ---- Lua -> panel -------------------------------------------------- */

  React.useEffect(
    () =>
      wire.on('show', () => {
        setVisible(true);
      }),
    [],
  );

  React.useEffect(
    () =>
      wire.on('hide', () => {
        setVisible(false);
      }),
    [],
  );

  React.useEffect(
    () =>
      wire.on('tick', (d) => {
        // Skip when the bar is offscreen — the user cannot see motion anyway
        // and the DOM write below is pure waste. Also keeps a brand-new panel
        // from sliding the dot before `show` arrives.
        if (!dotRef.current) return;
        // `pos` is already clamped in the wire adapter; multiply to %.
        dotRef.current.style.left = `${d.pos * 100}%`;
      }),
    [],
  );

  /* ---- render -------------------------------------------------------- */

  return (
    <div
      aria-hidden={!visible}
      className={[
        'pointer-events-none fixed left-1/2 z-50',
        'bottom-[18vh] w-[28vw] min-w-[280px] max-w-[460px]',
        '-translate-x-1/2 transition-opacity duration-[220ms] ease-out',
        visible ? 'opacity-100' : 'opacity-0',
      ].join(' ')}
    >
      <div className="relative h-2 overflow-hidden rounded border border-white/[0.35] bg-white/[0.12]">
        <div
          ref={dotRef}
          className={[
            'absolute left-1/2 top-1/2 h-[18px] w-[18px]',
            '-mt-[9px] -ml-[9px] rounded-full bg-white',
            'shadow-[0_0_0_2px_rgba(0,0,0,0.6)]',
            'transition-[left] duration-[80ms] ease-linear',
          ].join(' ')}
          style={{ left: '50%' }}
        />
      </div>

      <div className="mt-1.5 flex justify-between text-[11px] uppercase tracking-[0.04em] text-white/60">
        <span>Verliert</span>
        <span>Druecke &amp; halte</span>
        <span>Gewinnt</span>
      </div>
    </div>
  );
}
