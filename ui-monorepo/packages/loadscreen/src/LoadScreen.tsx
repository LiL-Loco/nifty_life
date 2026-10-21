import * as React from 'react';

import {
  DEFAULT_PHASE,
  PHASES,
  PHASE_EMOJI,
  type LoadingScreenMessage,
  type PhaseKey,
} from './loadscreen-contract';
import { createProgressModel } from './loadscreen-progress';

/**
 * The loading screen.
 *
 * WHY THE BAR HAS TWO SEGMENTS
 *
 * The engine reports the load as two counters that do not add up to one, and
 * both are 0..1:
 *
 *   - `initFunctionInvoking` gives `idx`/`count` over the init functions.
 *   - `performMapLoadFunction` gives `idx` over the data files, with the count
 *     announced separately by `startDataFileEntries`.
 *
 * Reading either of them as "the progress" fills the bar to 100% during the
 * init phase and then leaves it there for the whole map load — because the
 * data-file counter starts again at zero and a high-water mark refuses to
 * rewind. The player watches a full bar through the longest part of the wait.
 *
 * So the bar is composed: the init functions get the first quarter, the map
 * load the rest. The composition is monotone on its own, and the high-water
 * mark across it means it still cannot go backwards.
 *
 * WHY `loadFraction` IS BARELY USED, AND WHY IT IS NOT OUR FAULT
 *
 * `loadFraction` looks like the engine's own overall progress, and the official
 * documentation shows it as the way to drive a loading bar. It is not, in
 * normal operation.
 *
 * In `LoadingScreens.cpp` the fraction is computed as
 * `elapsed / g_loadTiming[1]`, and both `g_loadTiming[1]` and
 * `g_loadTimingBase` are assigned ONLY inside the `game_profileLoading`
 * branch. In the normal path `g_loadTiming` stays empty, `curTiming.count()`
 * is zero, and the whole computation is skipped. What the engine actually
 * sends in normal operation is `loadFraction: 0.0` when the map load starts
 * and `loadFraction: 1.0` when it ends. Nothing in between.
 *
 * It is still honoured when it carries a real fraction — a profiling run or a
 * game reload — because then it is the most accurate number available, and it
 * is the engine's own.
 *
 * WHY THE STALL GUARD EXISTS
 *
 * The composition is a heuristic and runs pessimistic when it is wrong: on a
 * slow disk the real load takes longer than the counters suggest, the fraction
 * stalls below 1, and the player watches a bar that will never reach the end on
 * a server that is in fact nearly done. Reaching 98% and then seeing nothing
 * new for a while means the estimate was low, not that the load hung — the
 * screen is about to disappear either way, and a full bar is the truthful
 * thing to show in the last second rather than 94%.
 */

const STALL_PERCENT = 0.98;
const STALL_MS = 20_000;
const EASE_PER_FRAME = 0.12;

export function LoadScreen() {
  const [phase, setPhase] = React.useState(DEFAULT_PHASE);
  const [emoji, setEmoji] = React.useState('');
  const [target, setTarget] = React.useState(0);
  const [shown, setShown] = React.useState(0);

  /**
   * The progress model lives in `loadscreen-progress.ts` and is pure — no
   * React, no DOM, no timers. It is a separate file because the bar is the one
   * thing on this screen whose correctness is a claim about a SEQUENCE of
   * messages, and a claim like that needs a test rather than a screenshot.
   * `verify-progress.ts` plays the engine's real message sequence through it.
   */
  const model = React.useRef(createProgressModel());

  const phaseSeen = React.useRef<Record<string, number>>({});
  const lastAdvance = React.useRef(Date.now());

  /** Take the model's answer and put it on the screen. */
  const raiseTo = React.useCallback((fraction: number) => {
    const next = Math.min(1, Math.max(0, fraction));
    setTarget((prev) => (next > prev ? next : prev));
    lastAdvance.current = Date.now();
  }, []);

  const settle = React.useCallback(() => setTarget(1), []);

  /** Feed one message to the model and take its composed progress. */
  const composed = React.useCallback((message?: LoadingScreenMessage) => {
    const state = message
      ? model.current.push(message)
      : model.current.snapshot();
    return state.target;
  }, []);

  /* ---- FiveM -> panel ------------------------------------------------
     Every handler below is transcribed from a named `InvokeNUIScript` call
     site in LoadingScreens.cpp. Nothing is inferred. */

  React.useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      const data = event.data as LoadingScreenMessage | undefined;
      if (!data || !data.eventName) return;

      switch (data.eventName) {
        case 'startInitFunctionOrder': {
          raiseTo(composed(data));

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
          raiseTo(composed(data));
          break;
        }

        case 'startDataFileEntries': {
          // The map load starts here. Its count is announced once and never
          // again, which is why `performMapLoadFunction` carries only an idx.
          raiseTo(composed(data));
          break;
        }

        case 'performMapLoadFunction': {
          raiseTo(composed(data));
          break;
        }

        case 'loadProgress': {
          // In normal operation this is 0.0 when the map load starts and 1.0
          // when it ends — see the note at the top. A real fraction in between
          // comes from a profiling run or a game reload, and then it is the
          // engine's own measurement of the whole load, which beats anything
          // counted here.
          if (typeof data.loadFraction === 'number' && data.loadFraction > 0) {
            raiseTo(composed(data));
          }
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
  }, [raiseTo, settle, composed]);

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
        </p>
      </div>

      <p className="hero-foot">Freitag 19:00 bis Sonntag 22:00 · Ein Charakter pro Person</p>
    </main>
  );
}