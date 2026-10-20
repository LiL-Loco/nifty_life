import {
  INIT_PHASE_COUNT,
  INIT_SEGMENT,
  type LoadingScreenMessage,
} from './loadscreen-contract';

/**
 * The progress model, as a pure function of the messages the engine sends.
 *
 * WHY IT IS NOT IN THE COMPONENT
 *
 * The bar is the one thing on this screen that has to be RIGHT, and "right"
 * is a claim about a sequence of messages that arrives over several seconds,
 * on a machine that is busy, with the player watching. Asserting that from
 * inside a React component means a test runner, a DOM and a fake clock for
 * something that is arithmetic over four numbers.
 *
 * So the model lives here: no React, no DOM, no timers. Feed it the messages
 * the engine sends and ask it where the bar should be. That is testable in
 * milliseconds, and the test can use the EXACT message sequence from
 * LoadingScreens.cpp.
 *
 * WHY THE MODEL IS PHASE-AWARE
 *
 * The engine reports two counters that are each 0..1 and neither of which is
 * the whole load:
 *
 *   - `initFunctionInvoking` — `idx`/`count` over the init functions, with
 *     `idx` RELATIVE TO THE CURRENT PHASE.
 *   - `performMapLoadFunction` — `idx` over the data files, with the count
 *     announced once by `startDataFileEntries`.
 *
 * Reading either as "the progress" fills the bar during the init phase and
 * then leaves it at 100% for the entire map load, which is the part that takes
 * the time. So the bar has two segments and the model composes them.
 */

export interface ProgressSnapshot {
  /** Where the bar should be, 0..1. */
  target: number;
  /** The init segment's own progress, 0..1. For diagnostics. */
  init: number;
  /** The map load's own progress, 0..1. For diagnostics. */
  map: number;
  /** True once the engine's own overall estimate was seen. */
  engineEstimate: boolean;
}

export interface ProgressModel {
  /** Feed one message. Returns the new state. */
  push(message: LoadingScreenMessage): ProgressSnapshot;
  /** The current state without feeding anything. */
  snapshot(): ProgressSnapshot;
}

/**
 * Build a model.
 *
 * The high-water mark lives here rather than in the component: the bar must
 * never rewind, and that is a property of the MODEL, not of how it is drawn.
 */
export function createProgressModel(): ProgressModel {
  /**
   * The init phases.
   *
   * `done` counts FINISHED phases, `idx`/`count` describe the current one.
   * The phases are worth one quarter each of the init segment, which is why
   * the count of phases comes from the contract rather than from a number here.
   */
  const init = { done: 0, idx: 0, count: 0, seen: '' };

  /** The data files. Its own 0..1, over the second segment. */
  const map = { idx: 0, count: 0 };

  /** The engine's own overall estimate, when it has one. */
  let engine = 0;
  let engineSeen = false;

  /** The high-water mark. The bar cannot rewind. */
  let high = 0;

  const compose = (): ProgressSnapshot => {
    const phaseFraction = init.count > 0 ? Math.min(1, init.idx / init.count) : 0;
    const initFraction = Math.min(
      1,
      (init.done + phaseFraction) / INIT_PHASE_COUNT,
    );

    const mapFraction = map.count > 0 ? Math.min(1, map.idx / map.count) : 0;

    // The map load owns the bar from the moment it starts. Before that, the
    // init segment does.
    const mine =
      map.count > 0
        ? INIT_SEGMENT + mapFraction * (1 - INIT_SEGMENT)
        : initFraction * INIT_SEGMENT;

    // The engine's estimate is measured against the real elapsed time, so when
    // it exists it beats anything counted here.
    const target = Math.max(mine, engine);

    if (target > high) high = target;

    return {
      target: high,
      init: initFraction,
      map: mapFraction,
      engineEstimate: engineSeen,
    };
  };

  const raise = (message: LoadingScreenMessage): ProgressSnapshot => {
    switch (message.eventName) {
      case 'startInitFunctionOrder': {
        // A new phase starts: the one before it is finished.
        if (init.seen !== '' && init.count > 0) init.done += 1;
        init.seen = message.type ?? '';
        init.idx = 0;
        init.count = message.count ?? 0;
        break;
      }

      case 'initFunctionInvoking': {
        // The message carries the count of the CURRENT phase, so nothing has to
        // be remembered from `startInitFunctionOrder` to read it.
        if (message.idx != null) init.idx = message.idx;
        if (message.count != null) init.count = message.count;
        break;
      }

      case 'startDataFileEntries': {
        // Announced once, never repeated. `performMapLoadFunction` carries
        // only an idx, so this is the only place the total comes from.
        if (message.count != null) map.count = message.count;
        break;
      }

      case 'performMapLoadFunction': {
        if (message.idx != null) map.idx = message.idx;
        break;
      }

      case 'loadProgress': {
        // In normal operation this is 0.0 when the map load starts and 1.0
        // when it ends. A real fraction in between comes from a profiling run
        // or a game reload, and then it is the engine's own measurement of the
        // whole load.
        if (typeof message.loadFraction === 'number' && message.loadFraction > 0) {
          engine = message.loadFraction;
          engineSeen = true;
        }
        break;
      }

      default:
        break;
    }

    return compose();
  };

  return {
    push: raise,
    snapshot: compose,
  };
}
