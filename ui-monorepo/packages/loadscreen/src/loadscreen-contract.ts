/**
 * The loading screen's contract, transcribed from the FiveM source.
 *
 * WHY THERE IS NO BRIDGE HERE
 *
 * Every other panel in this project talks to Lua through `@nifty/bridge`. The
 * loading screen cannot, and the difference is not a detail:
 *
 *   - It runs BEFORE any Lua VM exists. No `GetCurrentResourceName`, no
 *     `RegisterNUICallback`, no `SendNUIMessage` — there is nothing to talk
 *     to. Its only channel is `window.postMessage` pushed by the client.
 *   - Its message key is `eventName`, not `action`. Every NUI panel uses
 *     `action`. Copying the NUI shape here would be wrong twice over.
 *
 * The event list is taken from
 * `code/components/loading-screens-five/src/LoadingScreens.cpp` in
 * citizenfx/fivem, not from the stock example screen, which handles four of
 * them and ignores the rest.
 */

/** Exactly what FiveM pushes. Anything else is not from the client. */
export interface LoadingScreenMessage {
  eventName: string;
  count?: number;
  idx?: number;
  order?: number;
  type?: string;
  name?: string;
  loadFraction?: number;
  message?: string;
}

export type PhaseKey =
  | 'INIT_CORE'
  | 'INIT_BEFORE_MAP_LOADED'
  | 'INIT_AFTER_MAP_LOADED'
  | 'INIT_SESSION';

/**
 * The init phases, in the order the engine reports them.
 *
 * This used to be a table of EMOJI - one per phase, cycling through them as
 * the phases arrived, so the status line showed a fruit while the game
 * started. The emoji are gone; the LIST is not, because the bar's weighting
 * is derived from how many phases there are.
 */
export const INIT_PHASES: readonly PhaseKey[] = [
  'INIT_CORE',
  'INIT_BEFORE_MAP_LOADED',
  'INIT_AFTER_MAP_LOADED',
  'INIT_SESSION',
];

/**
 * How many init phases there are.
 *
 * Derived from the phase list rather than written down twice, because the
 * weighting of the bar depends on it: each phase is worth a quarter of the
 * init segment, and a phase that does not exist would make the bar jump.
 */
export const INIT_PHASE_COUNT = INIT_PHASES.length;

/**
 * WHICH PART OF THE BAR THE MAP LOAD GETS.
 *
 * The load has two parts that do not measure the same thing and do not add up
 * to one: the init functions (the game starting up) and the data files (the
 * map streaming in). The engine reports each of them as its own 0..1 counter,
 * and the naive reading — one counter, one bar — fills the bar completely
 * during the init phase and then leaves it at 100% for the whole map load,
 * which is the part that actually takes the time.
 *
 * So the bar has two segments. The split is a judgement call and it is stated
 * here so it can be argued with: the init functions are the game's own startup
 * and take a fraction of the wall clock, the map load is the wait.
 */
export const INIT_SEGMENT = 0.25;

/**
 * The five host-state transitions, verbatim from `printLog` in
 * LoadingScreens.cpp. English in, German out — the site is German and a panel
 * that blinks English lines through is a different product.
 */
export const PHASES: Record<string, string> = {
  'Entering session': 'Session wird verbunden',
  'Setting up game': 'Spiel wird vorbereitet',
  'Adjusting settings for best experience': 'Einstellungen werden angepasst',
  'Initializing session': 'Session wird initialisiert',
  'Starting game': 'Spiel startet',
};

export const DEFAULT_PHASE = 'Verbindung wird aufgebaut';