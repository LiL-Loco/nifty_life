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

/** Emoji the stock screen used, kept because they read as phases at a glance. */
export const PHASE_EMOJI: Record<PhaseKey, string> = {
  INIT_CORE: '🍇',
  INIT_BEFORE_MAP_LOADED: '🍉',
  INIT_AFTER_MAP_LOADED: '🍋🍊',
  INIT_SESSION: '🍐🍅🍆',
};

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