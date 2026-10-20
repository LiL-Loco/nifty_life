/**
 * The progress model, checked against the message sequence the engine sends.
 *
 * Run it:  bun run verify-progress
 *
 * WHY THIS EXISTS
 *
 * The loading bar was wrong in a way no type checker can see and no screenshot
 * would catch: it filled to 100% during the init phase and then stood there
 * through the entire map load, which is the part of the wait that actually
 * takes the time. The cause was that the engine reports the load as TWO
 * counters that are each 0..1, and reading either of them as "the progress"
 * does exactly that.
 *
 * The fix is a claim about a SEQUENCE of messages, so the claim needs a test.
 * The sequence below is transcribed from `LoadingScreens.cpp`:
 *
 *   - four init phases, each announced by `startInitFunctionOrder` with its
 *     own count, each filled by `initFunctionInvoking` with `idx` and `count`
 *   - the map load, announced once by `startDataFileEntries` with the count of
 *     the relevant data files, then one `performMapLoadFunction` per file
 *   - `loadProgress` with 0.0 when the map load starts and 1.0 when it ends
 *
 * The numbers are the shape the engine sends, not a recording of a session.
 */

import { createProgressModel } from './src/loadscreen-progress';
import type { LoadingScreenMessage } from './src/loadscreen-contract';

let failures = 0;

function check(name: string, condition: boolean, detail = '') {
  if (condition) {
    console.log(`  OK   ${name}${detail ? `  -> ${detail}` : ''}`);
  } else {
    failures += 1;
    console.log(`  FAIL ${name}${detail ? `  -> ${detail}` : ''}`);
  }
}

/** The four init phases, with the sizes the engine announces for them. */
const INIT_PHASES: { type: string; count: number }[] = [
  { type: 'INIT_CORE', count: 30 },
  { type: 'INIT_BEFORE_MAP_LOADED', count: 12 },
  { type: 'INIT_AFTER_MAP_LOADED', count: 9 },
  { type: 'INIT_SESSION', count: 41 },
];

/** The data files: the map load. */
const DATA_FILE_COUNT = 1200;

function runSequence() {
  const model = createProgressModel();
  const trace: { label: string; target: number }[] = [];

  const push = (m: LoadingScreenMessage, label: string) => {
    const s = model.push(m);
    trace.push({ label, target: s.target });
    return s;
  };

  for (const phase of INIT_PHASES) {
    push({ eventName: 'startInitFunctionOrder', type: phase.type, count: phase.count }, `order ${phase.type}`);
    for (let idx = 1; idx <= phase.count; idx += 1) {
      const s = push({ eventName: 'initFunctionInvoking', type: phase.type, idx, count: phase.count }, `init ${phase.type} ${idx}/${phase.count}`);
      if (idx === phase.count) {
        // The bar must NOT be full yet — the map load is still ahead.
        check(
          `Balken ist am Ende der Init-Phase NICHT voll (${phase.type})`,
          s.target < 1,
          `target=${s.target.toFixed(3)}`,
        );
      }
    }
  }

  // The map load starts. The engine sends loadFraction 0.0 here.
  push({ eventName: 'loadProgress', loadFraction: 0 }, 'loadProgress 0.0');

  const start = push({ eventName: 'startDataFileEntries', count: DATA_FILE_COUNT }, 'startDataFileEntries');
  check(
    'Nach startDataFileEntries ist der Balken NICHT voll',
    start.target < 1,
    `target=${start.target.toFixed(3)}`,
  );

  let last = start.target;
  let moved = false;
  for (let idx = 0; idx < DATA_FILE_COUNT; idx += 1) {
    const s = push({ eventName: 'performMapLoadFunction', idx }, `map ${idx}`);
    if (s.target > last) moved = true;
    last = s.target;
  }

  check(
    'Der Balken bewegt sich während des Kartenladens',
    moved,
    `letzter target=${last.toFixed(3)}`,
  );
  check(
    'Der Balken ist am Ende des Kartenladens fast voll',
    last > 0.9,
    `target=${last.toFixed(3)}`,
  );

  // The engine's final signal.
  const end = push({ eventName: 'loadProgress', loadFraction: 1 }, 'loadProgress 1.0');
  check('Am Ende steht der Balken auf 100%', end.target === 1, `target=${end.target}`);

  return trace;
}

console.log('== Fortschrittsmodell gegen die Nachrichtenfolge aus LoadingScreens.cpp ==');
const trace = runSequence();

console.log('\n== Verlauf (jeder 10. Schritt) ==');
for (let i = 0; i < trace.length; i += 10) {
  const t = trace[i];
  console.log(`  ${String(Math.round(t.target * 100)).padStart(3)}%  ${t.label}`);
}
const t = trace[trace.length - 1];
console.log(`  ${String(Math.round(t.target * 100)).padStart(3)}%  ${t.label}`);

console.log('\n== Regression: der alte Zaehler ==');
{
  // The old model: one counter, high-water mark. This is what the bar used to
  // do, and it is the bug.
  let oldHigh = 0;
  const oldRaise = (fraction: number) => {
    const next = Math.min(1, Math.max(0, fraction));
    if (next > oldHigh) oldHigh = next;
  };
  for (const phase of INIT_PHASES) {
    for (let idx = 1; idx <= phase.count; idx += 1) oldRaise(idx / phase.count);
  }
  check(
    'Der alte Zaehler waere am Ende der Init-Phase bei 100% (das war der Fehler)',
    oldHigh === 1,
    `oldHigh=${oldHigh}`,
  );
  console.log('  -> Genau deshalb stand der Balken die ganze Kartenhinweg voll.');
}

console.log(
  `\n${failures === 0 ? 'ALLE PRUEFUNGEN BESTANDEN' : `${failures} PRUEFUNG(EN) FEHLGESCHLAGEN`}`,
);
if (failures > 0) process.exit(1);
