import { createBridge, type Result } from '@nifty/ui';

/**
 * The Lua <-> NUI contract for nifty-clothing, transcribed from
 * `resources/[nifty]/nifty-clothing/client/cl_nui.lua` (the only file that
 * calls SendNUIMessage), `server/sv_owned.lua` and
 * `nifty-core/server/clothing.lua`.
 *
 * ---------------------------------------------------------------------------
 * WHAT THIS PORT FIXED, AND WHAT IT COULD NOT
 * ---------------------------------------------------------------------------
 *
 * Every action name below is the LUA string, never the JavaScript guess. The
 * old wardrobe.js / store.js switched on bare `'open'` and `'refresh'` while
 * Lua sent `'clothing:open'` and `'clothing:refresh'` — so the open push fell
 * through every case and the panel never unhid. Typing the Lua strings means
 * that class of mistake cannot compile again.
 *
 * THREE defects are fixed on the panel side, because the panel owns them:
 *
 *   1. `owned` is MERGED, not replaced. `clothing:refresh` carries exactly ONE
 *      (kind, slot) patch. `state.owned = data.owned` silently emptied the
 *      previously visited slot.
 *   2. `data.extra.*`, not `data.*`. wardrobe.js read `data.slots` /
 *      `data.character`; Lua nests them one level down.
 *   3. `storeList`'s key is `id` while every fetch it answers uses `slot_id`.
 *      Normalised on ingest by the caller.
 *
 * FIVE endpoints cannot work as written and this port deliberately does NOT
 * paper over them. Each call site below carries the reason. All five need a
 * Lua change, which this package is not allowed to make (hard constraint: no
 * file outside `packages/clothing/` may be touched).
 *
 *   a. equip          — the server handler needs a whole `appearance` table
 *                       (sv_owned.lua:440-479) and the payload never carries
 *                       one. The NUI cannot compute it: it has no access to
 *                       the player's current look. `cl_wardrobe.lua` already
 *                       has the two unused helpers (`getCurrentAppearance`,
 *                       `snapshotCurrent`, lines 75-91) that would build it.
 *   b. unequip        — `nifty:server:clothingUnequip` has no handler anywhere.
 *   c. saveOutfit     — same `appearance` problem (sv_owned.lua:601-623).
 *   d. deleteOutfit   — `tostring(tonumber(data.id) or '')` turns a UUID into
 *   e. applyOutfit    — `''`, because outfit ids are CHAR(36). renameOutfit's
 *                       server handler proves a plain string is accepted, so
 *                       this `tonumber` is pure damage. Outfit ids are passed
 *                       through verbatim here so the panel is correct the
 *                       moment Lua stops corrupting them.
 *   f. purchaseItem   — Lua hardcodes `collection = ''` and the server rejects
 *                       an empty collection (sv_owned.lua:392). `StoreItem`
 *                       therefore carries an OPTIONAL `collection` and the
 *                       call site forwards it when present: the store is a
 *                       read-only catalogue until `Price.listForSlot` also
 *                       SELECTs `collection`.
 */

/* ------------------------------------------------------------------ shapes */

export type Kind = 'component' | 'prop';

/** One owned row as built by sv_owned.lua:532-549. There is NO `id` field. */
export interface Piece {
  kind: string;
  slot_id: number;
  collection: string;
  drawable: number;
  texture: number;
  /** Already carries ' (von X)' when `acquired_from` is set. */
  name: string;
  base_name: string;
  source: string;
  /** Key ABSENT (not null) when the column is NULL. */
  acquired_from?: string | null;
}

/** nifty-core/server/clothing.lua:293-309. `id` is a UUID, not a number. */
export interface Outfit {
  id: string;
  name: string;
  created_at: string;
  /** Key ABSENT when NULL. */
  applied_at?: string | null;
  pieces: number;
}

/** nifty-core/server/clothing.lua:627-648 — the query selects these four. */
export interface StoreItem {
  drawable: number;
  texture: number;
  name: string | null;
  price: number;
  /** Not on the wire today. See purchaseItem note (f) above. */
  collection?: string;
}

/**
 * A patch for exactly ONE (kind, slot): `owned[kind][slot] = items`.
 * Numeric slot keys arrive in JS as string keys, hence `Record<string, …>`.
 */
export type OwnedPatch = Partial<Record<Kind, Record<string, Piece[]>>>;

export interface WardrobeSlots {
  components: number[];
  props: number[];
}

/** Absent when the account/character row is missing; each field can be null. */
export interface CharacterName {
  firstName: string | null;
  lastName: string | null;
}

/**
 * `data.mode` — not the action string — is what separates the two screens.
 * wardrobe.js and store.js each attached to the same `message` stream and
 * filtered the other one out by hand with four lines comparing against strings
 * no message ever used. That collapses into one discriminated union.
 */
export type ClothingOpen =
  | {
      mode: 'wardrobe';
      extra: { slots?: WardrobeSlots; character?: CharacterName | null };
    }
  | {
      mode: 'store';
      extra: { storeId?: string | number };
    };

/** The two halves of `ClothingOpen`, named for the screens that render them. */
export type WardrobeOpen = Extract<ClothingOpen, { mode: 'wardrobe' }>;
export type StoreOpen = Extract<ClothingOpen, { mode: 'store' }>;

/** Two payload shapes share this one action; each key is independent. */
export interface RefreshData {
  owned?: OwnedPatch;
  /** Full replacement list. */
  outfits?: Outfit[];
}

/** `id`, NOT `slot_id` — cl_nui.lua:145 rewrites the server's `slot`. */
export interface StoreListData {
  kind: Kind;
  id: number;
  items: StoreItem[];
}

/** The raw server table, passed through untouched (`data or {}`). */
export type PurchaseReply =
  | {
      ok: true;
      kind: string;
      slot_id: number;
      collection: string;
      drawable: number;
      texture: number;
      price: number;
    }
  | { ok: false; reason: string };

/* ------------------------------------------------------------------ bridge */

/**
 * A `type` alias, not an `interface`: TypeScript grants implicit index
 * signatures to object-literal aliases but NOT to interfaces, and
 * `createBridge<T extends ActionMap>` needs one to infer.
 */
type ClothingActions = {
  'clothing:open': (data: ClothingOpen) => void;
  /** Lua sends literally `{ action = 'clothing:close' }` — no `data` key. */
  'clothing:close': (data: undefined) => void;
  'clothing:refresh': (data: RefreshData) => void;
  storeList: (data: StoreListData) => void;
  purchaseResult: (data: PurchaseReply) => void;
};

export const clothingBridge = createBridge<ClothingActions>({
  received: [
    'clothing:open',
    'clothing:close',
    'clothing:refresh',
    'storeList',
    'purchaseResult',
  ],
});

type Empty = Record<string, never>;

/** Every RegisterNUICallback in cl_nui.lua, with the body it actually reads. */
type ClothingCallbacks = {
  /** Broadcasts `clothing:close` to the NUI and releases focus. */
  closePanel: Empty;
  /**
   * Sends `slot`, the server reads `payload.slot_id` — no reply ever comes
   * back. Kept as-is: the panel cannot fix the key from this side.
   */
  getOwnedForSlot: { kind: Kind; id: number };
  /** See note (b): the server event has no handler anywhere. */
  unequip: { kind: Kind; id: number };
  /** See note (a): `pieceId` satisfies Lua's truthiness guard, nothing more. */
  equip: { kind: Kind; id: number; pieceId: number };
  /** Stacks a one-shot Lua handler per call; the panel guards its own calls. */
  getOutfits: Empty;
  /** See note (c). */
  saveOutfit: { name: string };
  /** See notes (d/e): the UUID goes through verbatim, `tonumber` stays in Lua. */
  deleteOutfit: { id: string };
  renameOutfit: { id: string; name: string };
  applyOutfit: { id: string };
  /** The one fetch that really reaches the server: correct `slot_id` key. */
  getStoreListForSlot: { kind: Kind; id: number };
  /** See note (f). */
  purchaseItem: {
    kind: Kind;
    slot_id: number;
    drawable: number;
    texture: number;
    collection: string;
  };
};

/**
 * Every outbound call goes through here, so a callback name that no longer
 * exists on the Lua side fails the build instead of turning into a 404 that
 * only shows up as a button that does nothing.
 */
export function send<K extends keyof ClothingCallbacks & string>(
  name: K,
  body: ClothingCallbacks[K],
): Promise<Result<{ ok: true }>> {
  return clothingBridge.call<{ ok: true }>(name, body);
}

/* ----------------------------------------------------------------- payloads */

/**
 * Stand-in for the `pieceId` that cl_nui.lua's `equip` guard requires.
 *
 * A piece has no server-side id — it is keyed by collection + drawable +
 * texture — and the server ignores this value anyway because it rejects the
 * payload before it looks at it. `drawable` is the piece's real numeric
 * identity, so nothing here is invented, but the button cannot work until the
 * Lua side builds the `appearance` table. See note (a).
 */
export function pieceIdOf(piece: Piece): number {
  return piece.drawable;
}