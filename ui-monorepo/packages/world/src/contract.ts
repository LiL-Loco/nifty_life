import { createBridge, type Result } from '@nifty/bridge';

/**
 * The nifty-world Lua <-> NUI contract, typed.
 *
 * WHAT THE NUI ACTUALLY RECEIVES
 *
 * Only two actions reach this browser: `render` and `result`. Every other net
 * event (`nifty:client:economy`, `nifty:client:inventory`, `nifty:client:jobs`,
 * `nifty:client:shop`, `nifty:client:enterWorld`, …) is consumed by
 * client/cl_world.lua, which mutates its local `State` and re-sends the WHOLE
 * thing as one `render`. That is deliberate — one message per change instead of
 * one per subsystem, so the panel never renders half an update — and it is why
 * this file has exactly two action names and not twenty.
 *
 * The events cl_world.lua handles but never forwards (`nifty:client:openCreator`,
 * `nifty:client:creatorError`, `nifty:client:welcomeCutscene`) are therefore
 * absent on purpose. Adding them here would be a lie the type system then
 * enforces forever.
 */

/* ------------------------------------------------------------------ shapes */

export interface Money {
  cash: number;
  bank: number;
}

/** One row of `Inventory:view()` — nifty-inventory/server/inventory.lua. */
export interface InventoryItem {
  id: string | number;
  slot: number;
  code: string;
  name: string;
  category: string;
  isWeapon: boolean;
  quantity: number;
  unitWeight: number;
  metadata?: unknown;
}

export interface InventoryView {
  items: InventoryItem[];
  usedSlots: number;
  totalSlots: number;
  usedWeight: number;
  maxWeight: number;
}

/** One freemode component or prop: `components[3]`, `props[0]`, … */
export interface Garment {
  collection: string;
  drawable: number;
  texture: number;
}

export interface HeadBlend {
  mother: string;
  father: string;
  third: string;
  motherWeight: number;
  fatherWeight: number;
  thirdWeight: number;
  skinTone: number;
}

export interface Overlay {
  style: number;
  opacity: number;
  colourType?: number;
  colour?: number;
  secondColour?: number;
}

export interface HairColour {
  primary: number;
  highlight: number;
}

export interface HairOverlay {
  collection: string;
  preset: string;
  opacity?: number;
}

export interface Tattoo {
  collection: string;
  preset: string;
}

/**
 * The decoded `characters.appearance` JSON column.
 *
 * The panel does not read this yet, but it is on the wire on every render and
 * the inventory panel's OUTFIT section is specified to read it (cl_world.lua
 * lines 121-128). Typing it as `unknown` — or omitting it — would make that
 * work fail silently rather than loudly.
 */
export interface Appearance {
  model: string;
  components: Record<number, Garment>;
  props: Record<number, Garment>;
  headBlend: HeadBlend;
  eyeColour: number;
  faceFeatures: Record<number, number>;
  overlays: Record<number, Overlay>;
  hairColour: HairColour;
  hairOverlay?: HairOverlay;
  tattoos: Tattoo[];
}

export type Gender = 'male' | 'female' | 'nonbinary';

export interface Character {
  id: string;
  firstName: string;
  lastName: string;
  dateOfBirth: string | null;
  gender: Gender;
  appearance: Appearance | null;
  /** Key into SpawnPoints. Informational only — the coords travel in data.spawn. */
  spawnPoint: string;
}

/** `Jobs:listFor(characterId)` — only what this character signed up for. */
export interface JobAssignment {
  code: string;
  name: string;
  kind: string;
  onDuty: boolean;
  dutySince: string | null;
}

/** `Jobs:list()` — the whole roster, with wages. */
export interface JobCatalogueEntry {
  code: string;
  name: string;
  kind: string;
  isEmergency: boolean;
  base: { x: number; y: number; z: number };
  wagePerHour: number;
}

/** `Shop:catalogue()`. */
export interface ShopEntry {
  code: string;
  name: string;
  category: string;
  price: number;
  stackable: boolean;
  maxStack: number;
}

/** `Ownership:listProperties()`. */
export interface PropertyEntry {
  id: string;
  code: string;
  name: string;
  district: string;
  tier: string;
  kind: string;
  owned: boolean;
  ownerId: string | null;
  entrance: { x: number; y: number; z: number };
}

/** `Ownership:listVehicles(characterId)`. */
export interface VehicleEntry {
  id: string;
  model: string;
  plate: string;
  x: number;
  y: number;
  z: number;
  heading: number;
  fuel: number;
  engineHealth: number;
  bodyHealth: number;
  stored: boolean;
}

/**
 * What `render` looks like ON THE WIRE.
 *
 * Every field is optional, because a Lua table simply has no key for a nil
 * value: `SendNUIMessage` drops it on the way to JSON. `render.data.panel` is
 * absent exactly when the panel is closed, and `data.character` is absent
 * before the character has ever been pushed. Typing them as required would be
 * a claim the server does not make.
 */
export interface RenderPayload {
  money?: Money;
  inventory?: InventoryView;
  character?: Character | null;
  jobs?: JobAssignment[];
  jobCatalogue?: JobCatalogueEntry[];
  shop?: ShopEntry[];
  properties?: PropertyEntry[];
  vehicles?: VehicleEntry[];
  /**
   * `RegisterCommand('niftypanel', …)` sets this to whatever `State[name]`
   * matched, and cl_world.lua forwards the name verbatim — so the wire type is
   * a plain string, not a union of the two panels this panel can draw. Narrowing
   * it to `'shop' | 'jobs'` would break the build the day somebody adds a
   * `properties` builder, which is the good outcome.
   */
  panel?: string | null;
}

/** What the panel holds after merging a `render` onto what it already had. */
export interface WorldState {
  money: Money;
  inventory: InventoryView;
  character: Character | null;
  jobs: JobAssignment[];
  jobCatalogue: JobCatalogueEntry[];
  shop: ShopEntry[];
  properties: PropertyEntry[];
  vehicles: VehicleEntry[];
  panel: string | null;
}

export interface ResultPayload {
  ok: boolean;
  message: string;
}

/**
 * The two actions this panel accepts. Nothing else is legal.
 *
 * A `type` and not an `interface`, and this is not a style preference: an
 * INTERFACE gets no implicit index signature from TypeScript, so this map could
 * not satisfy `ActionMap = Record<string, unknown>` and every `bun run typecheck`
 * in this package failed with "Index signature for type 'string' is missing" —
 * pointing at the constraint rather than at the one keyword that differs. It has
 * been failing since the panel was written.
 */
type WorldActions = {
  render: RenderPayload;
  result: ResultPayload;
};

const bridge = createBridge<WorldActions>({ received: ['render', 'result'] });

/* --------------------------------------------------------------- callbacks */

/**
 * Every `RegisterNUICallback` in client/cl_world.lua, with the body it actually
 * reads. `send('buy', { code })` does not compile — the quantity is not
 * optional there, and `send('puch', …)` never will.
 *
 * These four are wired by nifty-inventory and nifty-housing on their own
 * frames; they stay declared here because they are registered by THIS
 * resource's Lua, and an undeclared name is the failure mode @nifty/bridge
 * exists to prevent.
 */
export interface WorldCallbacks {
  closePanel: Record<string, never>;
  buy: { code: string; quantity: number };
  sell: { code: string; quantity: number };
  deposit: { amount: number };
  withdraw: { amount: number };
  jobJoin: { code: string };
  jobLeave: { code: string };
  dutyStart: { code: string };
  dutyEnd: { code: string };
  useItem: { code: string; quantity: number };
  moveItem: { from: number; to: number };
  acquireProperty: { id: string };
}

/** Fire a Lua callback. Returns a Result, never throws. */
export function send<K extends keyof WorldCallbacks>(
  name: K,
  body: WorldCallbacks[K],
): Promise<Result<unknown>> {
  return bridge.call(name, body);
}

/* ------------------------------------------------------------ subscriptions */

/**
 * Subscribe to `render`. Returns the unsubscribe function — hand it straight
 * back from a `useEffect`, which is the whole reason this panel is React and
 * not 200 lines of `window.addEventListener` with no teardown.
 */
export function onRender(handler: (data: RenderPayload) => void): () => void {
  return bridge.on('render', handler);
}

/** Subscribe to `result`. Same teardown contract. */
export function onResult(handler: (data: ResultPayload) => void): () => void {
  return bridge.on('result', handler);
}

/* ---------------------------------------------------------------- defaults */

export const EMPTY_INVENTORY: InventoryView = {
  items: [],
  usedSlots: 0,
  totalSlots: 0,
  usedWeight: 0,
  maxWeight: 0,
};

export const INITIAL_STATE: WorldState = {
  money: { cash: 0, bank: 0 },
  inventory: EMPTY_INVENTORY,
  character: null,
  jobs: [],
  jobCatalogue: [],
  shop: [],
  properties: [],
  vehicles: [],
  panel: null,
};