import * as React from 'react';

import {
  DEFAULT_PHASE,
  PHASES,
  PHASE_EMOJI,
  type LoadingScreenMessage,
  type PhaseKey,
} from './loadscreen-contract';

/**
 * The loading screen.
 *
 * WHY THE PROGRESS IS TWO NUMBERS AND NOT ONE
 *
 * FiveM reports load progress from three counters that do not agree: an
 * `initFunctionInvoking` index, a `performMapLoadFunction` index, and a
 * `loadFraction` that is `elapsed / total` against a PREDICTED total. The
 * stock screen counts the first two into one variable that
 * `startDataFileEntries` then overwrites, which is why its bar restarts — its
 * own comment admits it.
 *
 * So: `target` is a high-water mark across all three, and `shown` eases toward
 * it. The bar can never rewind, and it cannot outrun the game.
 *
 * WHY THE STALL GUARD EXISTS
 *
 * `loadFraction` is a heuristic and runs pessimistic when it is wrong: on a slow
 * disk the real load takes longer than predicted, the fraction stalls below 1,
 * and the player watches a bar that will never reach the end on a server that
 * is in fact nearly done. Reaching 98% and then seeing nothing new for a while
 * means the estimate was low, not that the load hung — the screen is about to
 * disappear either way, and a full bar is the truthful thing to show in the
 * last second rather than 94%.
 */

const STALL_PERCENT = 0.98;
const STALL_MS = 20_000;
const EASE_PER_FRAME = 0.12;

export function LoadScreen() {
  const [phase, setPhase] = React.useState(DEFAULT_PHASE);
  const [emoji, setEmoji] = React.useState('');
  const [target, setTarget] = React.useState(0);
  const [shown, setShown] = React.useState(0);

  const initCount = React.useRef(0);
  const dataCount = React.useRef(0);
  const phaseSeen = React.useRef<Record<string, number>>({});
  const lastAdvance = React.useRef(Date.now());

  /** Raise the high-water mark. A lower number from a later source is stale. */
  const raiseTo = React.useCallback((fraction: number) => {
    const next = Math.min(1, Math.max(0, fraction));
    setTarget((prev) => (next > prev ? next : prev));
    lastAdvance.current = Date.now();
  }, []);

  const settle = React.useCallback(() => setTarget(1), []);

  /* ---- FiveM -> panel ------------------------------------------------
     Every handler below is transcribed from a named `InvokeNUIScript` call
     site in LoadingScreens.cpp. Nothing is inferred. */

  React.useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      const data = event.data as LoadingScreenMessage | undefined;
      if (!data || !data.eventName) return;

      switch (data.eventName) {
        case 'startInitFunctionOrder': {
          if (data.count != null) initCount.current = data.count;
          const key = (data.type ?? '') as PhaseKey;
          const glyphs = PHASE_EMOJI[key];
          if (glyphs) {
            const seen = (phaseSeen.current[key] ?? 0) + 1;
            phaseSeen.current[key] = seen;
            setEmoji(glyphs[seen - 1] ?? '');
          }
          break;
        }

        case 'initFunctionInvoking': {
          const count = initCount.current;
          if (count > 0 && data.idx != null) raiseTo(data.idx / count);
          break;
        }

        case 'startDataFileEntries': {
          if (data.count != null) dataCount.current = data.count;
          setEmoji('🍕');
          break;
        }

        case 'performMapLoadFunction': {
          const count = dataCount.current;
          if (count > 0 && data.idx != null) raiseTo(data.idx / count);
          break;
        }

        case 'loadProgress': {
          if (typeof data.loadFraction === 'number') raiseTo(data.loadFraction);
          break;
        }

        case 'onLogLine': {
          const german = PHASES[data.message ?? ''];
          // A miss leaves the phase alone. An English line from the engine is
          // not a reason to put English on a German screen.
          if (german) {
            setPhase(german);
            // "Starting game" is the last host-state transition before the data
            // is handed to the session. Nothing is left to count after it.
            if (german === PHASES['Starting game']) settle();
          }
          break;
        }

        case 'networkInited':
          settle();
          break;

        default:
          break;
      }
    };

    window.addEventListener('message', onMessage);
    return () => window.removeEventListener('message', onMessage);
  }, [raiseTo, settle]);

  /* ---- the eased bar ------------------------------------------------- */

  React.useEffect(() => {
    let raf = 0;
    const tick = () => {
      setShown((prev) => {
        if (prev >= target) return prev;
        const next = prev + (target - prev) * EASE_PER_FRAME;
        return target - next < 0.001 ? target : next;
      });
      raf = window.requestAnimationFrame(tick);
    };
    raf = window.requestAnimationFrame(tick);
    return () => window.cancelAnimationFrame(raf);
  }, [target]);

  /* ---- the stall guard ------------------------------------------------ */

  React.useEffect(() => {
    const id = window.setInterval(() => {
      if (target > shown && target >= STALL_PERCENT) {
        if (Date.now() - lastAdvance.current > STALL_MS) settle();
      }
    }, 1000);
    return () => window.clearInterval(id);
  }, [target, shown, settle]);

  const percent = Math.floor(shown * 100);

  return (
    <main className="hero">
      <div className="hero-mark">
        <span className="hero-mark-top">Nifty</span>
        <span className="hero-mark-bottom">Life</span>
        <span className="hero-mark-version">2.0</span>
      </div>

      <div className="stage">
        <div
          className="pill"
          role="progressbar"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={percent}
          aria-label="Ladefortschritt"
          data-running={percent > 0 && percent < 100 ? '1' : '0'}
        >
          <div className="pill-fill" style={{ width: `${percent}%` }} />
        </div>

        <p className="stage-status" role="status" aria-live="polite">
          {phase}
          {emoji ? <span className="stage-emoji">{emoji}</span> : null}
        </p>
      </div>

      <p className="hero-foot">Freitag 19:00 bis Sonntag 22:00 · Ein Charakter pro Person</p>
    </main>
  );
}