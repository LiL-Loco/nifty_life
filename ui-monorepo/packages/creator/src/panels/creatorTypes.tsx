import * as React from 'react';
import { Button, Slider, createBridge, cn, type Result } from '@nifty/ui';

/**
 * The creator's shared, state-free contract.
 *
 * WHY THIS FILE EXISTS AT ALL
 *
 * `createBridge` only gives a wrong action name a COMPILE error when every panel
 * shares ONE action map. Twelve panels each declaring their own map would let
 * `send('pickModle', …)` through in nine of them, because a map that lists nine
 * actions cannot check a tenth call site that uses the tenth action. So the map
 * below is declared once, here, from `client/cl_nui.lua` — every name transcribed
 * from the RegisterNUICallback / SendNUIMessage literals, never guessed.
 *
 * It also holds the four presentational widgets every panel needs. The vanilla
 * app.js had `button()`, `separator()`, `list()` and `slider()` as local
 * factories, re-instantiated per panel; two of them leaked a pair of window
 * listeners on every pointer-down. These are React components with the same
 * visual shape and no listeners to leak.
 *
 * Nothing here holds module state. The only mutable thing is the shell's.
 *
 * ---------------------------------------------------------------------------
 * KNOWN GAPS ON THE LUA SIDE — these are NOT fixable from here (no .lua file may
 * be touched), so the panels degrade instead of erroring:
 *
 * 1. `buildPayload` (cl_nui.lua:146-162) forwards 12 keys and drops seven:
 *    faceGroups, parentNames, componentLabels, propLabels, overlayLabels,
 *    zoneLabels, maxTexture. `applyOpen` guards each with `if (data.X)`, so they
 *    keep their defaults. Consequence: `state.parentNames` is ALWAYS empty
 *    today (see the baked-in fallback in panels/Parents.tsx) and the outfit /
 *    makeup / tattoo rows show 'Slot 3' instead of 'Oberteil'.
 * 2. `labels.MOTHER` / `labels.FATHER` are Lua FUNCTIONS (cl_labels.lua:172-179),
 *    not arrays. A function cannot survive JSON, so those two label sets never
 *    arrive. The real arrays are `Labels.MOTHER_NAMES` / `Labels.FATHER_NAMES`,
 *    which getState already forwards as `parentNames` — see (1).
 * 3. `Labels.THIRDPERSON` IS a real array and DOES arrive inside `labels`.
 * 4. `faceGroups.FACE_1D` / `FACE_2D` read two globals that nothing in the
 *    resources tree assigns, so they always arrive as `{}`.
 * 5. `captureParentPortrait` returns `''` (cl_creator.lua:62,1337), so the
 *    `creator:parentPortraits` push carries two empty strings. It is
 *    deliberately NOT wired to the portrait <img>; see Parents.tsx.
 */

/* ------------------------------------------------------------------ lua shapes */

/** One frame of the face-bone overlay, pushed at 30 Hz. */
export interface FaceBone {
  name: string;
  /** Already PIXELS — GetScreenCoordFromWorldCoord output. */
  x: number;
  y: number;
}

/** The full object `setOverlay` replaces. Lua does not patch fields. */
export interface Overlay {
  style: number;
  opacity: number;
  colourType: number;
  colour: number;
  secondColour: number;
}

export interface SlotSelection {
  collection: string;
  drawable: number;
  texture: number;
}

/** One entry of `slots[kind][String(id)]`. Only `slot[0]` is ever read. */
export interface SlotOption {
  /**
   * NOTE: renderSlot passes `option.name` as the COLLECTION to setSlot
   * (app.js:1018,1029). Whether that is intended or a leftover is unresolved;
   * the type keeps both fields so a fix is a one-line change, not a reshape.
   */
  name: string;
  collection?: string;
  drawables: number;
  textures: number;
}

/** Payload of the `creator:itemNames` push, keyed `${kind}:${id}`. */
export interface ItemNames {
  drawables: number;
  textures: number;
  /** drawable -> texture -> display name. */
  names: Record<string, Record<string, string>>;
}

export interface TattooEntry {
  collection: string;
  hashName: string;
  preset: number;
  name: string;
  zone: number;
}

/** cl_creator.lua:155-162. `resemblance` is NOT in the constructor. */
export interface HeadBlend {
  mother: number;
  father: number;
  third: number;
  motherWeight: number;
  fatherWeight: number;
  thirdWeight: number;
  skinTone: number;
  /**
   * Created by the first Aehnlichkeit drag and read by nothing else: Lua does
   * `face.headBlend[k] = v` for whatever key arrives. See Parents.tsx.
   */
  resemblance?: number;
}

export interface FaceState {
  /** Keyed by STRING — Lua stores `features[tostring(id)]`. SPARSE. */
  features: Record<string, number>;
  /** Keyed by STRING — same reason as features. */
  overlays: Record<string, Overlay>;
  hairColour: { primary: number; highlight: number };
  hairOverlay: { collection: string; preset: string; opacity: number } | null;
  /** Dead: nothing reads `face.tattoos`; tattoos live in `state.tattoos`. */
  tattoos?: unknown[];
  eyeColour: number;
  headBlend: HeadBlend;
}

/** FACE_2D entries carry BOTH axes; FACE_1D only left/right. */
export interface FaceGroup2D {
  xId: number;
  yId: number;
  title: string;
  left: string;
  right: string;
  top: string;
  bottom: string;
}

export interface FaceGroup1D {
  id: number;
  title: string;
  left: string;
  right: string;
}

export interface LabelSet {
  /** NEVER ARRIVES — a Lua function. See Parents.tsx for the fallback. */
  MOTHER?: string[];
  /** NEVER ARRIVES — a Lua function. */
  FATHER?: string[];
  /** A real 46-entry array of names. Does arrive. */
  THIRDPERSON?: string[];
  EYE_COLOURS?: string[];
  /** Indexed by String(id); index 0 is always the off-slot. */
  OVERLAY_STYLES?: Record<string, string[]>;
  /** Present but never read by any renderer. */
  FEATURES?: string[];
}

export interface Palettes {
  /** 26 x [r, g, b, a]. */
  HAIR_PALETTE?: number[][];
  /** Undefined global in Lua — always arrives empty. */
  MAKEUP_PALETTE?: number[][];
  /** Undefined global in Lua — always arrives empty. */
  OVERLAY_PALETTES?: Record<string, [number, string, number[]][]>;
}

export interface CreatorState {
  modelIsUndecided: boolean;
  face: FaceState;
  /** Keyed by String(slotId). */
  selection: { components: Record<string, SlotSelection>; props: Record<string, SlotSelection> };
  slots: { components: Record<string, SlotOption[]>; props: Record<string, SlotOption[]> };
  labels: LabelSet;
  palettes: Palettes;
  /** Real string arrays — but dropped by buildPayload, so usually empty. */
  parentNames: { mother: string[]; father: string[] };
  componentLabels: Record<string, string>;
  propLabels: Record<string, string>;
  overlayLabels: Record<string, string>;
  zoneLabels: Record<string, string>;
  faceGroups: { FACE_1D: FaceGroup1D[]; FACE_2D: FaceGroup2D[] };
  itemNames: Record<string, ItemNames>;
  tattoos: { zones: number[] | null; byZone: Record<number, TattooEntry[]> };
}

/** `creator:open` — buildPayload's twelve keys, verbatim. */
export type CreatorOpen = CreatorState;

/** `creator:refresh` — a partial patch, NOT a full state dump. */
export interface CreatorRefresh {
  selection?: CreatorState['selection'];
  face?: Partial<FaceState>;
  skinCam?: 'face' | 'body';
  slots?: CreatorState['slots'];
}

/* ------------------------------------------------------------------ the bridge */

type CreatorActions = {
  'creator:open': (data: CreatorOpen) => void;
  'creator:refresh': (data: CreatorRefresh) => void;
  /** Sent literally without a `data` key. */
  'creator:close': (data: undefined) => void;
  'creator:error': (data: { message: string }) => void;
  'creator:faceBones': (data: { bones: FaceBone[] }) => void;
  'creator:itemNames': (data: { kind: string; id: number; names: ItemNames }) => void;
  'creator:tattooZones': (data: { zones: number[] }) => void;
  'creator:tattoosByZone': (data: { zoneId: number; tattoos: TattooEntry[] }) => void;
  'creator:parentPortraits': (data: { mother: string; father: string }) => void;
};

export const creatorBridge = createBridge<CreatorActions>({
  received: [
    'creator:open',
    'creator:refresh',
    'creator:close',
    'creator:error',
    'creator:faceBones',
    'creator:itemNames',
    'creator:tattooZones',
    'creator:tattoosByZone',
    'creator:parentPortraits',
  ],
});

type Empty = Record<string, never>;

/**
 * Every RegisterNUICallback in cl_nui.lua, with the body it actually reads.
 *
 * NOTE a deliberate omission of two contracts this port must not invent:
 * `getItemNames` reads an undefined global `state` in cl_creator.lua:1291 (the
 * live table is the file-local `slots`), so it throws and no names ever arrive;
 * `setSlot` never calls sendRefresh(), so no echo comes back either. Both are
 * panel-side problems for the slot group to handle, not types to work around
 * here.
 */
type CreatorCallbacks = {
  closePanel: Empty;
  setFaceBonesActive: { active: boolean };
  getItemNames: { kind: string; id: number };
  setSlot: { kind: string; id: number; slot: SlotSelection };
  setFeature: { id: number; value: number };
  setOverlay: { id: number; overlay: Overlay };
  setHairColour: { channel: 'primary' | 'highlight'; index: number };
  setHairOverlayOpacity: { opacity: number };
  setEyeColour: { index: number };
  /** ONE key per call: Lua loops the table and does `headBlend[k] = v`. */
  setHeadBlend: Partial<HeadBlend>;
  randomise: Empty;
  randomiseAll: Empty;
  reset: Empty;
  submit: Empty;
  cancel: Empty;
  zoomIn: Empty;
  zoomOut: Empty;
  camYaw: { delta: number };
  showSkinCam: { kind: 'face' | 'body' };
  /** Lua sets `modelIsUndecided = false` and re-derives the gender from the hash. */
  pickModel: { model: string };
  pickTattoo: { zoneId: number; collection: string; preset: number };
  removeTattoo: { zoneId: number };
  swapOverlayPalette: { id: number; paletteIndex: number };
  getTattooZones: Empty;
  getTattoosByZone: { zoneId: number };
  /** Returns '' from a stub export — see Parents.tsx before wiring this up. */
  requestParentPortraits: Empty;
  tickFaceBones: Empty;
};

/** The only way a panel talks to Lua. Never throws — inspect `.ok`. */
export function send<K extends keyof CreatorCallbacks & string>(
  name: K,
  body: CreatorCallbacks[K],
): Promise<Result<{ ok: true }>> {
  return creatorBridge.call<{ ok: true }>(name, body);
}

/* ---------------------------------------------------------------- navigation */

export type CreatorPanelKind =
  | 'root'
  | 'heritage'
  | 'parents'
  | 'eyeColour'
  | 'faceFeatures'
  | 'hair'
  | 'makeup'
  | 'overlay'
  | 'outfit'
  | 'slot'
  | 'tattoos'
  | 'tattooZone';

export interface PanelNav {
  /** The only way to LEAVE a panel. There is no back button; ESC pops. */
  pushPanel: (kind: CreatorPanelKind, payload?: Record<string, unknown>) => void;
  /** Returns false at depth 1, which is the ESC handler's cue to closeAll. */
  popPanel: () => boolean;
}

/* ------------------------------------------------------------------ widgets */

/**
 * A full-width menu row: label, optional dim description, trailing chevron.
 *
 * The vanilla `button()` also took `primary` and `danger`, which map onto the
 * shared Button's variant + border colour rather than a new component.
 */
export function Row({
  label,
  desc,
  onClick,
  chevron = true,
  variant = 'default',
  disabled,
}: {
  label: string;
  desc?: string | null;
  onClick: () => void;
  chevron?: boolean;
  variant?: 'default' | 'primary' | 'danger';
  disabled?: boolean;
}) {
  return (
    <Button
      variant={variant === 'danger' ? 'destructive' : 'ghost'}
      disabled={disabled}
      onClick={onClick}
      className={cn(
        'h-auto w-full items-start justify-start gap-3 whitespace-normal rounded-[var(--radius-panel)] px-4 py-3 text-left text-[14px] font-semibold normal-case tracking-normal hover:border-[var(--color-amber)] hover:bg-[var(--color-accent)]',
        variant === 'primary' && 'border-[var(--color-amber)] text-[var(--color-amber)] hover:brightness-110',
        variant === 'danger' && 'border-destructive',
      )}
    >
      <span className="min-w-0 flex-1">
        <span className="block font-semibold">{label}</span>
        {desc ? (
          <span className="mt-0.5 block text-[11px] font-normal text-[var(--color-muted-foreground)]">
            {desc}
          </span>
        ) : null}
      </span>
      {chevron ? (
        <span aria-hidden className="mt-0.5 shrink-0 text-[18px] text-[var(--color-muted-foreground)]">
          ›
        </span>
      ) : null}
    </Button>
  );
}

/** Section heading — the vanilla `separator()`. */
export function Caption({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-2 mb-1 mt-3 text-[10px] font-semibold uppercase tracking-[0.18em] text-[var(--color-muted-foreground)]">
      {children}
    </div>
  );
}

/**
 * A stepped picker: ‹ label value ›.
 *
 * The vanilla `list()` kept `cur` in the widget's own closure and only wrote it
 * back into the DOM, so a step waited for Lua's refresh to be acknowledged
 * before it moved again — two quick clicks collapsed into one. Here the value is
 * derived from props and the click is applied optimistically; the `sentRef`
 * guard is what re-syncs when the value changes from OUTSIDE (reset, randomise).
 */
export function List({
  label,
  items,
  index,
  onChange,
}: {
  label: string;
  items: string[];
  index: number;
  onChange: (index: number) => void;
}) {
  const [cur, setCur] = React.useState(index);
  const sentRef = React.useRef(index);

  React.useEffect(() => {
    // Anything that is not the echo of our own click has to win.
    if (index !== sentRef.current) {
      sentRef.current = index;
      setCur(index);
    }
  }, [index]);

  const step = React.useCallback(
    (delta: number) => {
      // Computed OUTSIDE the updater on purpose: a side effect inside a state
      // updater runs twice under StrictMode, and every one of these is a POST
      // to Lua that also pushes a refresh back.
      const next = Math.max(0, Math.min(items.length - 1, cur + delta));
      if (next === cur) return;
      sentRef.current = next;
      setCur(next);
      onChange(next);
    },
    [cur, items.length, onChange],
  );

  const value = items[cur];

  return (
    <div className="flex items-center overflow-hidden rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-background)] transition-colors hover:border-[var(--color-amber)] focus-within:border-[var(--color-amber)]">
      <button
        type="button"
        aria-label={'‹ ' + label}
        disabled={cur <= 0}
        onClick={() => step(-1)}
        className="h-11 w-9 shrink-0 bg-transparent text-[20px] leading-none text-[var(--color-amber)] disabled:cursor-not-allowed disabled:text-[var(--color-muted-foreground)]"
      >
        ‹
      </button>
      <div className="min-w-0 flex-1 px-2 py-1.5 text-center">
        <span className="block text-[10px] uppercase tracking-[0.12em] text-[var(--color-muted-foreground)]">
          {label}
        </span>
        <span className="mt-0.5 block overflow-hidden text-ellipsis whitespace-nowrap text-[14px] text-[var(--color-foreground)]">
          {value}
        </span>
      </div>
      <button
        type="button"
        aria-label={label + ' ›'}
        disabled={cur >= items.length - 1}
        onClick={() => step(1)}
        className="h-11 w-9 shrink-0 bg-transparent text-[20px] leading-none text-[var(--color-amber)] disabled:cursor-not-allowed disabled:text-[var(--color-muted-foreground)]"
      >
        ›
      </button>
    </div>
  );
}

/**
 * A labelled 0..max slider in INDEX space, exactly like the vanilla `slider()`:
 * the caller maps the step index to whatever unit the Lua side wants
 * (`i / 100` for the 101-entry Aehnlichkeit list, `i / 1000` for the 1001-entry
 * weight list). The two giant label arrays are therefore never materialised.
 *
 * THE `draft` STATE IS NOT OPTIMISM, IT IS CORRECTNESS. Every one of these
 * sliders is controlled by a value that only arrives after a Lua round-trip, and
 * a radix Slider driven by a stale prop visibly snaps backwards mid-drag. The
 * draft is dropped only once the echo lands, so a value that never comes back
 * (setSlot does not refresh) still leaves the thumb where the player put it.
 */
export function LabeledSlider({
  label,
  value,
  max,
  format,
  onChange,
}: {
  label: string;
  /** Step index, already clamped to 0..max by the caller. */
  value: number;
  max: number;
  format: (index: number) => string;
  onChange: (index: number) => void;
}) {
  const [draft, setDraft] = React.useState<number | null>(null);

  React.useEffect(() => {
    if (draft !== null && draft === value) setDraft(null);
  }, [draft, value]);

  const shown = draft !== null ? draft : value;

  return (
    <div className="rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-background)] px-4 py-3 transition-colors hover:border-[var(--color-amber)] focus-within:border-[var(--color-amber)]">
      <div className="mb-2 flex items-baseline justify-between gap-3">
        <span className="text-[11px] uppercase tracking-[0.12em] text-[var(--color-muted-foreground)]">
          {label}
        </span>
        <span className="text-[13px] tabular-nums text-[var(--color-amber)]">{format(shown)}</span>
      </div>
      <Slider
        aria-label={label}
        min={0}
        max={max}
        step={1}
        value={[shown]}
        onValueChange={(v: number[]) => {
          const next = v[0];
          setDraft(next);
          onChange(next);
        }}
        onValueCommit={() => setDraft(null)}
      />
    </div>
  );
}