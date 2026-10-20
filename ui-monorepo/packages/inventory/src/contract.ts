/**
 * The nifty-inventory Lua <-> NUI contract, as types.
 *
 * Source of truth: resources/[nifty]/nifty-inventory/client/cl_inventory.lua.
 * The panel's Lua side never changes in this migration, so everything the
 * resource actually puts on the wire is transcribed here once. A field that is
 * not in this file does not exist as far as the panel is concerned.
 *
 * The three actions below go through `createBridge`, which is the only reason a
 * renamed or misspelled prefix is a compile error instead of a panel that
 * silently never opens. That failure is not hypothetical: every NUI frame on the
 * client shares one `SendNUIMessage` channel, so an unprefixed name is heard by
 * every resource at once.
 */

import { createBridge } from '@nifty/ui';

/* ------------------------------------------------------------------ Lua -> NUI */

export interface InventoryItem {
  /** `Nifty.newUuid()`, arrives as a JSON string. */
  id: string;
  /** 0-based inventory slot. On the wire; the panel renders by list order. */
  slot: number;
  code: string;
  /** Falls back to `code` when the code is not in item_defs. */
  name: string;
  /** Falls back to the literal 'unknown'. */
  category: string;
  isWeapon: boolean;
  quantity: number;
  /**
   * The weight of ONE unit, not the row's weight. The header's `usedWeight` is
   * summed server-side, so a tile that shows `unitWeight` alone contradicts the
   * header for every stack — the row weight is `unitWeight * quantity`.
   */
  unitWeight: number;
  /**
   * The column is nullable, so this key is OMITTED, not null. Known keys:
   * `giver_name` (stamped by nifty-clothing after a give/pickup), `outfit_id`,
   * and accessory tuples.
   */
  metadata?: Record<string, unknown> & { giver_name?: string };
}

export interface InventoryView {
  /** Ordered by `slot` ASC. */
  items: InventoryItem[];
  /** Count of ROWS, not the sum of quantities. */
  usedSlots: number;
  totalSlots: number;
  usedWeight: number;
  maxWeight: number;
}

export interface AppearanceSlot {
  collection: string;
  drawable: number;
  texture: number;
}

export interface Character {
  id: string;
  firstName: string;
  lastName: string;
  dateOfBirth: string;
  gender: string;
  spawnPoint: string;
  /**
   * OMITTED when the column is NULL. Keys of `components` / `props` are
   * STRINGIFIED slot ids ("3"), never numbers.
   */
  appearance?: {
    model?: string;
    components?: Record<string, AppearanceSlot>;
    props?: Record<string, AppearanceSlot>;
  };
}

/** The payload of both `inventory:open` and `inventory:refresh`, byte for byte. */
export interface InventoryPush {
  inventory: InventoryView;
  /**
   * Absent — not null — until an `nifty:client:enterWorld` arrives. On a
   * refresh, absent means "keep the character I already have", NOT "clear it".
   */
  character?: Character;
}

/* ------------------------------------------------------------------ NUI -> Lua */

export type UseItemBody = { code: string; quantity: number; itemId: string };
export type DiscardGroundBody = { code: string; quantity: number; itemId: string };
/** `quantity` is how many STAY in the original row, not how many move. */
export type SplitStackBody = { itemId: string; quantity: number };
export type EnterGiveModeBody = { code: string; itemId: string; quantity: number };
/**
 * `targetSrc` must be a NUMBER: Lua guards `type(data.targetSrc) ~= 'number'`
 * and rejects a string outright.
 *
 * `quantity` is deliberately NOT sent. cl_inventory.lua ignores it and takes the
 * quantity from the giveMode latch that `enterGiveMode` stored, so putting it on
 * the wire would be decorative. The old app.js sent it anyway.
 */
export type ConfirmGiveBody = { targetSrc: number };

export type SimpleOk = { ok: true };

/** NO `position` key — the doc comment at cl_inventory.lua L242 claims one. */
export interface NearbyPlayer {
  src: number;
  name: string;
  distance: number;
}

export type EnterGiveModeRes = { ok: true; targets: NearbyPlayer[] } | { ok: false };
export type ConfirmGiveRes =
  | { ok: true }
  | { ok: false; reason?: 'no give mode' | 'no target' };

/* ------------------------------------------------------------------ the bridge */

/**
 * A `type`, not an `interface`, on purpose: only type aliases get the implicit
 * index signature that satisfies `createBridge`'s `ActionMap` constraint. With an
 * interface this would not compile at all; with this alias `bridge.on` is
 * restricted to these three exact strings.
 */
type InventoryActions = {
  'inventory:open': (body: InventoryPush) => void;
  'inventory:refresh': (body: InventoryPush) => void;
  'inventory:close': () => void;
};

export const bridge = createBridge<InventoryActions>({
  received: ['inventory:open', 'inventory:refresh', 'inventory:close'],
});

/**
 * Typed wrappers for the resource's `RegisterNUICallback` handlers.
 *
 * `callLua` never returns null — it answers `{ ok: false, error }` on a failed
 * request, a timeout or a throw. The old fetchNui returned `null` in all three
 * cases and two call sites destructured `{ ok, targets }` straight off it, so a
 * single hiccup was an unhandled `TypeError: Cannot destructure property 'ok' of
 * null`. Every call site below goes through `Result`.
 *
 * `discardItem` and `refreshTargets` are registered in Lua and are NOT listed
 * here: the shipped panel has never called either, and inventing a call site for
 * them would be a behaviour change dressed up as a port.
 */
export const lua = {
  closePanel: () => bridge.call<SimpleOk>('closePanel'),
  useItem: (body: UseItemBody) => bridge.call<SimpleOk>('useItem', body),
  discardItemOnGround: (body: DiscardGroundBody) =>
    bridge.call<{ ok: boolean; reason?: 'no ped' | 'no coords' }>('discardItemOnGround', body),
  splitStack: (body: SplitStackBody) => bridge.call<SimpleOk>('splitStack', body),
  enterGiveMode: (body: EnterGiveModeBody) => bridge.call<EnterGiveModeRes>('enterGiveMode', body),
  exitGiveMode: () => bridge.call<SimpleOk>('exitGiveMode'),
  confirmGive: (body: ConfirmGiveBody) => bridge.call<ConfirmGiveRes>('confirmGive', body),
};

/* ------------------------------------------------------------------ formatting */

/** Same formatter the old panel used, including the de-DE separators. */
export function money(n: number | string | undefined): string {
  const v = Number(n) || 0;
  return v.toLocaleString('de-DE', {
    minimumFractionDigits: v % 1 === 0 ? 0 : 2,
    maximumFractionDigits: 2,
  });
}

/* ------------------------------------------------------------------ appearance */

const COMPONENT_NAMES: Record<number, string> = {
  1: 'Maske', 2: 'Haar', 3: 'Oberkörper', 4: 'Hose', 5: 'Schuhe',
  6: 'Socken', 7: 'Jacke', 8: 'Unterhemd', 9: 'Krawatte',
  10: 'Gürtel', 11: 'Oberteil',
};

const PROP_NAMES: Record<number, string> = {
  0: 'Mütze', 1: 'Brille', 2: 'Ohrring', 3: 'Uhr', 4: 'Armband', 5: 'Ring',
};

export interface WornItem {
  /** e.g. "Oberkörper #3", "Ring #12", "Slot 14 #0". */
  label: string;
}

/**
 * Flatten `character.appearance` into display rows for the OUTFIT section.
 *
 * This is the ONLY thing the panel reads out of `character`; `model`,
 * `faceFeatures`, `overlays`, `hairColour`, `tattoos`, `eyeColour` and
 * `headBlend` all travel on the wire and are all ignored here.
 */
export function wornItems(appearance: Character['appearance']): WornItem[] {
  if (!appearance || typeof appearance !== 'object') return [];

  const out: WornItem[] = [];

  const labelFor = (kind: 'component' | 'prop', slotId: number, drawable: number) => {
    if (kind === 'component') {
      return `${COMPONENT_NAMES[slotId] || `Slot ${slotId}`} #${drawable}`;
    }
    return `${PROP_NAMES[slotId] || `Prop ${slotId}`} #${drawable}`;
  };

  const read = (
    source: Record<string, AppearanceSlot> | undefined,
    kind: 'component' | 'prop',
  ) => {
    if (!source) return;
    for (const key of Object.keys(source)) {
      const slotId = Number(key);
      const slot = source[key];
      if (!slot || Number.isNaN(slotId)) continue;
      out.push({ label: labelFor(kind, slotId, slot.drawable) });
    }
  };

  read(appearance.components, 'component');
  read(appearance.props, 'prop');
  return out;
}