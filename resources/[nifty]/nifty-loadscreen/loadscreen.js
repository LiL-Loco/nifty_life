/*[[
  Nifty Life loading screen — progress and phase.

  Two jobs, and the second one is the reason this file exists at all:

    1. Show progress that never lies. FiveM reports load progress from three
       independent counters that do not agree with each other, so the bar takes
       the MAXIMUM of all of them and is then eased toward that maximum. It
       cannot move backwards, and it cannot outrun the game.

    2. Say something in German. FiveM emits its load phases in English
       ("Adjusting settings for best experience"). Those are mapped to German
       here, and — this is the deliberate part — an UNRECOGNISED line changes
       nothing. A whitelist, not a fallback: showing the raw English would put
       the only English text on an otherwise German surface, right where the
       player is watching most closely.

  Vanilla JS, no modules, no build step (ADR-0002), same as every other nifty
  UI. The loading screen runs before the Lua VM exists, so this file cannot
  assume any project code is loaded.
]] */

/* --------------------------------------------------------------------------
   Phases. A match REPLACES the text; a miss leaves it alone.

   The five entries are the complete set of lines FiveM prints while the host
   state changes (LoadingScreens.cpp, `printLog` call sites). `OnScriptInitStatus`
   carries one line per resource being started and is not in this list — those
   arrive as arbitrary text and are deliberately not surfaced.
   -------------------------------------------------------------------------- */

const PHASES = {
  'Entering session': 'Session wird verbunden',
  'Setting up game': 'Spiel wird vorbereitet',
  'Adjusting settings for best experience': 'Einstellungen werden angepasst',
  'Initializing session': 'Session wird initialisiert',
  'Starting game': 'Spiel startet',
};

const DEFAULT_PHASE = 'Verbindung wird aufgebaut';

const fillEl = document.getElementById('fill');
const statusEl = document.getElementById('status');
const pillEl = document.querySelector('.pill');

/* The highest fraction any source has claimed. Kept as a running maximum
   because the three counters restart at different times and an unguarded
   assignment is exactly what makes the stock bar jump. */
let target = 0;

/* What the player actually sees. Lags `target` and closes the gap per frame,
   so a source that jumps 30% -> 90% in one event still reads as a load. */
let shown = 0;

/* The two counter families FiveM reports, kept apart. The stock loading screen
   reuses ONE `count` for both and overwrites it at every phase change, which is
   why its bar restarts; separate slots is the whole fix. */
let initIdx = 0;
let initCount = 0;
let dataIdx = 0;
let dataCount = 0;

/* Set once the last source has been seen. The bar eases to 100% on its own
   from here; nothing has to tell it to finish. */
const settle = () => {
  target = 1;
};

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

/* Any source that reports counts as progress for the stall guard below, even
   when the value it carries is one we already had — otherwise a run of
   repeated events at a fixed fraction would look stalled while the load is
   plainly still moving. */
let lastAdvance = Date.now();

function raiseTo(fraction) {
  const next = clamp01(fraction);
  // `target` is a high-water mark, never a value. A source that reports a
  // LOWER number than one already seen is stale, not a regression.
  if (next > target) target = next;
  lastAdvance = Date.now();
}

function setPhase(text) {
  if (statusEl.textContent !== text) statusEl.textContent = text;
}

/* --------------------------------------------------------------------------
   The frame loop.

   `shown` chases `target` with an exponential ease. The constant is a
   per-frame fraction, not a duration, so the bar behaves the same at 30fps and
   at 144fps. 0.12 lands roughly two-thirds of the remaining gap in 100ms —
   fast enough that it never feels like the bar is stuck, slow enough that a
   five-percent source step is visible as motion rather than a cut.
   -------------------------------------------------------------------------- */

let lastPainted = -1;

function tick() {
  if (shown < target) {
    shown += (target - shown) * 0.12;
    if (target - shown < 0.001) shown = target;
  }

  // Repaint only on whole percent. The element has a CSS transition on top of
  // this, and updating it at 60fps defeats that by restarting the transition
  // every frame.
  const percent = Math.floor(shown * 100);
  if (percent !== lastPainted) {
    lastPainted = percent;
    fillEl.style.width = percent + '%';
    pillEl.setAttribute('aria-valuenow', String(percent));
  }

  requestAnimationFrame(tick);
}

/* --------------------------------------------------------------------------
   FiveM's events.

   Payload shapes are taken from the loading-screens-five source, not from
   guesswork — the stock example's payloads are used by it but are not
   documented anywhere a reader would look.
   -------------------------------------------------------------------------- */

const handlers = {
  /* 0..1 from the game's own timing. Fired once per timing mark rather than
     per frame, so it is a target, not a stream. */
  loadProgress(data) {
    raiseTo(data.loadFraction);
  },

  startInitFunctionOrder(data) {
    initCount = data.count || 0;
  },

  /* `idx` arrives already incremented, and the game appends a synthetic
     `FinalizeLoad` step beyond the real count — hence the clamp. */
  initFunctionInvoking(data) {
    initIdx = data.idx || 0;
    if (initCount > 0) raiseTo(initIdx / initCount);
  },

  startDataFileEntries(data) {
    dataCount = data.count || 0;
  },

  performMapLoadFunction(data) {
    dataIdx = data.idx || dataIdx + 1;
    if (dataCount > 0) raiseTo(dataIdx / dataCount);
  },

  onLogLine(data) {
    const german = PHASES[data.message];
    if (german) {
      setPhase(german);
      // "Starting game" is the last host-state transition before the data is
      // handed to the session. Nothing is left to count after it.
      if (german === PHASES['Starting game']) settle();
    }
  },

  networkInited() {
    settle();
  },
};

window.addEventListener('message', function (e) {
  const data = e.data;
  if (!data || !data.eventName) return;
  const handler = handlers[data.eventName];
  if (handler) handler(data);
});

/* --------------------------------------------------------------------------
   The stall guard.

   The game's own progress estimate is a heuristic and can be wrong in the
   pessimistic direction: `loadFraction` is `elapsed / total` against a
   predicted total, and on a slow disk the real load takes longer than predicted
   — so the fraction stalls below 1 and the player watches a bar that will
   never reach the end, on a server that is in fact nearly done.

   Reaching 98% and then seeing nothing new for a while means the estimate was
   low, not that the load hung: the screen is about to disappear anyway, and a
   full bar is the truthful thing to show in the last second rather than 94%.
   Twenty seconds is long enough to outlast any real pause between load phases
   and short enough that nobody reads it as a stutter.
   -------------------------------------------------------------------------- */

setInterval(function () {
  if (target > shown && target >= 0.98) {
    if (Date.now() - lastAdvance > 20000) settle();
  }
}, 1000);

/* --------------------------------------------------------------------------
   Debug harness: open index.html?debug=1 in any browser.

   The loading screen cannot be driven by hand once it is on the server, so the
   event stream is replayed here instead. The deliberately ugly jump (0.3, then
   again 0.3, then 0.9) is there to prove the bar does not rewind — which is
   the bug the stock screen has.
   -------------------------------------------------------------------------- */

if (location.search.includes('debug')) {
  let i = 0;
  const script = [
    ['startInitFunctionOrder', { type: 'INIT_CORE', order: 1, count: 12 }],
    ['initFunctionInvoking', { idx: 4, count: 12 }],
    ['loadProgress', { loadFraction: 0.3 }],
    ['loadProgress', { loadFraction: 0.3 }], // duplicate: must not restart anything
    ['startDataFileEntries', { count: 5 }],
    ['performMapLoadFunction', { idx: 5 }],
    ['loadProgress', { loadFraction: 0.9 }], // jump forward
    ['initFunctionInvoking', { idx: 7, count: 12 }],
    ['onLogLine', { message: 'Entering session' }],
    ['onLogLine', { message: 'Adjusting settings for best experience' }],
    ['onLogLine', { message: 'something we do not recognise' }], // must be ignored
    ['onLogLine', { message: 'Starting game' }],
  ];
  const timer = setInterval(function () {
    if (i >= script.length) {
      clearInterval(timer);
      return;
    }
    const [eventName, payload] = script[i++];
    handlers[eventName] && handlers[eventName](payload);
  }, 700);
}

requestAnimationFrame(tick);