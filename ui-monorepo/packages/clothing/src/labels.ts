/**
 * Slot labels.
 *
 * These NEVER arrive from Lua. `clothing:open` sends `slots` and `character`
 * and nothing else; wardrobe.js read `data.componentLabels` /
 * `data.propLabels` off a payload that does not contain them, so the map was
 * always empty and every button fell back to `Slot <n>`.
 *
 * The tables therefore live here as module constants, ONCE. cl_wardrobe.lua
 * and cl_store.lua each keep their own Lua copy and store.js kept a third JS
 * copy; nothing keeps them in sync. They will stay in sync the day Lua hoists
 * them into the open push — the two call sites below are the only readers.
 *
 * The three fallback strings are NOT interchangeable, because the two old
 * screens each had their own. They are kept apart on purpose:
 *
 *   wardrobeSlotLabel -> `prop 9` / `component 9`
 *   storeRootLabel    -> `Prop 9`  / `Slot 9`
 *   storeSlotLabel    -> `Prop 9`  / `Slot 9`  / `Slot 9`
 */

import type { Kind } from './contract';

export const COMPONENT_LABELS: Record<number, string> = {
  1: 'Masken',
  2: 'Haare',
  3: 'Oberkoerper',
  4: 'Hosen',
  5: 'Schuhe',
  7: 'Accessoires',
  8: 'Unterhemden',
  11: 'Oberteile',
};

export const PROP_LABELS: Record<number, string> = {
  0: 'Kopfbedeckung',
  1: 'Brille',
  2: 'Ohrring',
  6: 'Schmuck',
  7: 'Uhr',
};

/**
 * The store has no slot list either: `clothing:open` in store mode carries
 * only `{ storeId }`, and the server picks the price list itself. So the
 * browsable catalogue is the fixed hardware slot set the shop stocks, exactly
 * as store.js hardcoded it.
 */
export const STORE_COMPONENT_SLOTS: readonly number[] = [1, 2, 3, 4, 5, 7, 8, 11];

export const STORE_PROP_SLOTS: readonly number[] = [0, 1, 2, 6, 7];

/** wardrobe.js:127-129 — `(labels[id]) || (kind + ' ' + id)`. */
export function wardrobeSlotLabel(kind: Kind, id: number): string {
  const label = kind === 'prop' ? PROP_LABELS[id] : COMPONENT_LABELS[id];
  return label || `${kind} ${id}`;
}

/** store.js:82 / :95 — `componentLabels[s] || 'Slot ' + s`, `propLabels[s] || 'Prop ' + s`. */
export function storeRootLabel(kind: Kind, id: number): string {
  if (kind === 'component') return COMPONENT_LABELS[id] || `Slot ${id}`;
  return PROP_LABELS[id] || `Prop ${id}`;
}

/** store.js:109-113. */
export function storeSlotLabel(kind: Kind, id: number): string {
  if (kind === 'component') return COMPONENT_LABELS[id] || `Slot ${id}`;
  if (kind === 'prop') return PROP_LABELS[id] || `Prop ${id}`;
  return `Slot ${id}`;
}