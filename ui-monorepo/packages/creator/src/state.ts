import type {
  CreatorState,
  FaceState,
  HeadBlend,
  SlotSelection,
  TattooEntry,
  ItemNames,
} from './panels/creatorTypes';

/**
 * The creator's typed store.
 *
 * WHY THIS IS A FACTORY AND NOT A DEFAULT-LITERAL CONSTANT
 *
 * `creatorTypes.tsx:170-187` declares `CreatorState` with seven required keys,
 * four of which (`labels`, `palettes`, `faceGroups`, `tattoos`) Lua forwards as
 * either absent or empty. The store has to live before any of those arrive, but
 * it must still be the same TYPE the panels read later — TS is exactly what
 * catches a panel that reads `state.palettes.OVERLAY_PALETTES[id]` without a
 * nullish-guard fallback.
 *
 * `EMPTY_STATE` is therefore a fully-typed CreatorState whose every required
 * key is populated, with empty nested objects that the panels' `?? []` / `?? {}`
 * fallbacks already expect. Faking the type with `as unknown as CreatorState`
 * turns that guarantee off and lets a missing field look like a typed key.
 *
 * MERGE BEHAVIOUR
 *
 * `applyOpen` replaces the top-level slices it understands and keeps the rest
 * (NOTHING is preserved across an open: cl_creator.lua treats it as a fresh
 * character), so this store mirrors Lua's "snapshot, not patch" approach.
 *
 * `applyRefresh` MERGES instead. cl_nui.lua's sendRefresh hands back
 * `selection` / `face` / `slots`; it does NOT include `componentLabels`,
 * `propLabels`, `overlayLabels`, `zoneLabels`, `parentNames` or `faceGroups` —
 * those arrive only at open time. Preserving them across a refresh is the only
 * way the outfit list, the parent portraits and the face-feature groups stay
 * populated while a slider drag echoes back. The merge helpers below
 * (`mergeSelection`, `mergeFace`) preserve the slot/string keys that the refresh
 * leaves alone and replace the ones it includes.
 */

/* --------------------------------------------------------------- EMPTY_STATE */

/**
 * A CreatorState with no data — what a brand-new panel sees before
 * `creator:open` lands.
 *
 * Every key is present so the shape matches `CreatorState` exactly; the
 * nested records are EMPTY so the panels' `?? []` / `?? {}` guards pass
 * without TypeScript errors.
 */
export function createEmptyState(): CreatorState {
  return {
    modelIsUndecided: false,
    face: {
      features: {},
      overlays: {},
      hairColour: { primary: 0, highlight: 0 },
      hairOverlay: null,
      eyeColour: 0,
      headBlend: {
        mother: 0,
        father: 0,
        third: 0,
        motherWeight: 0,
        fatherWeight: 0,
        thirdWeight: 0,
        skinTone: 0.5,
      },
    },
    selection: { components: {}, props: {} },
    slots: { components: {}, props: {} },
    labels: {},
    palettes: {},
    parentNames: { mother: [], father: [] },
    componentLabels: {},
    propLabels: {},
    overlayLabels: {},
    zoneLabels: {},
    faceGroups: { FACE_1D: [], FACE_2D: [] },
    itemNames: {},
    tattoos: { zones: null, byZone: {} },
  };
}

/* --------------------------------------------------------------- replace */

/**
 * Apply a `creator:open` payload to the current state.
 *
 * Every top-level field the payload carries WINS; the rest are dropped — the
 * old code did exactly the same (`applyOpen` in app.js:1168-1193 only sets
 * fields that exist in `data`, but a creator open is the boundary of a fresh
 * session, not an in-place mutation). This keeps the type happy on the
 * `label.MOTHER = []` / `label.MOTHER = function` branch the old code lost:
 * if Lua sends `labels.MOTHER`, we forward it; if not, the empty default the
 * store was built with stays empty.
 */
export function applyOpen(prev: CreatorState, data: Partial<CreatorState>): CreatorState {
  return {
    ...prev,
    ...data,
  } as CreatorState;
}

/**
 * Apply a `creator:refresh` payload to the current state, MERGING partial
 * slices rather than replacing wholesale.
 *
 * The refresh carries `selection` / `face` / `slots` full and nothing else
 * (cl_nui.lua:222-229). `componentLabels`, `propLabels`, `overlayLabels`,
 * `zoneLabels`, `parentNames`, `faceGroups`, `itemNames`, `tattoos` are
 * preserved across refreshes — losing them on every gesture would empty out
 * the outfit list, the parent portraits and the face-feature groups. The
 * helpers below replace only what's in the patch.
 */
export function applyRefresh(prev: CreatorState, data: Partial<CreatorState>): CreatorState {
  const next: CreatorState = {
    ...prev,
    ...data,
    face: data.face ? mergeFace(prev.face, data.face) : prev.face,
    selection: data.selection ? mergeSelection(prev.selection, data.selection) : prev.selection,
  };
  return next;
}

/* --------------------------------------------------------------- merges */

/**
 * Merge a partial face patch with the existing face.
 *
 * `face` itself is replaced wholesale by the patch — `mergeFace` in app.js:55
 * spreads every key into `prev.face`, but the type system here makes that
 * harder and the effect is identical: every key the refresh carries wins,
 * every key it doesn't stays. Head blend is the ONE nested record that needs
 * per-key merging, because the patch may carry `mother` without `father`, and
 * the parents panel reads every field. Skipping the partial merge on
 * headBlend would clobber six keys when one is updated.
 */
export function mergeFace(prev: FaceState, patch: Partial<FaceState>): FaceState {
  const headBlend: HeadBlend = patch.headBlend
    ? { ...prev.headBlend, ...patch.headBlend }
    : prev.headBlend;
  return {
    ...prev,
    ...patch,
    headBlend,
  };
}

/**
 * Merge a partial selection patch with the existing selection.
 *
 * `selection.components[id]` and `.props[id]` are individual slot records —
 * preserving the OTHER slots across a patch is what keeps a shirt pick from
 * wiping the player's hat choice. Each per-slot record itself replaces
 * wholesale (a fresh drawable IS the new state).
 */
export function mergeSelection(
  prev: CreatorState['selection'],
  patch: Partial<CreatorState['selection']>,
): CreatorState['selection'] {
  const out: CreatorState['selection'] = {
    components: { ...prev.components },
    props: { ...prev.props },
  };
  for (const kind of ['components', 'props'] as const) {
    const byId = patch[kind];
    if (!byId) continue;
    for (const [id, slot] of Object.entries(byId)) {
      out[kind][id] = slot as SlotSelection;
    }
  }
  return out;
}

/* --------------------------------------------------------------- itemNames */

/**
 * Insert one entry into `state.itemNames`, keyed by `kind:id`.
 *
 * `state.itemNames` is the cross-panel cache. `creator:itemNames` carries a
 * single `{kind, id, names}` triple; the cache holds MANY of them at once,
 * so this is the typed merge.
 */
export function upsertItemNames(
  prev: CreatorState,
  entry: { kind: string; id: number; names: ItemNames },
): CreatorState['itemNames'] {
  return {
    ...prev.itemNames,
    [`${entry.kind}:${entry.id}`]: entry.names,
  };
}

/**
 * Derive the summary line for one row of the outfit list (app.js:926).
 *
 * The outfit row's description was the per-slot drawable+texture name from
 * `state.itemNames`, falling back to 'Leer' / `Modell {drawable+1}`. The shells
 * owns it because the cache lives at shell scope. Body-overlay rows use '–'
 * because the legacy slotSummary had no real name for them and the Lua cache
 * never carries overlay names — OutfitPanel falls back to '–' for those rows.
 */
export function slotSummary(
  selection: CreatorState['selection'],
  itemNames: CreatorState['itemNames'],
  kind: 'components' | 'props',
  id: number,
): string {
  const slot = selection[kind][String(id)] as SlotSelection | undefined;
  if (!slot) return 'Leer';
  const drawable = parseInt(String(slot.drawable), 10) || 0;
  const texture = parseInt(String(slot.texture), 10) || 0;
  const cache = itemNames[`${kind}:${id}`];
  const hit = cache?.names?.[String(drawable)]?.[String(texture)];
  return hit ?? `Modell ${drawable + 1}`;
}

/* --------------------------------------------------------------- tattoos */

/**
 * Patch one zone's tattoo list, preserving the others.
 *
 * `creator:tattoosByZone` carries `{zoneId, tattoos}`. Replacing the whole
 * `tattoos.byZone` record would lose every other zone the player has loaded.
 */
export function upsertTattoosByZone(
  prev: CreatorState['tattoos'],
  zoneId: number,
  list: TattooEntry[],
): CreatorState['tattoos'] {
  return {
    ...prev,
    byZone: { ...prev.byZone, [zoneId]: list },
  };
}

/* --------------------------------------------------------------- overlayLabel */

/**
 * Build the overlay label map from `state.overlayLabels` only.
 *
 * `state.overlayLabels` is the map buildPayload is supposed to forward; it
 * arrives empty because cl_nui.lua:146-162 does not include it. The shell
 * falls back to `Overlay ${id}` strings the panel renders verbatim, so the
 * out-of-the-box build is identical to the legacy build. Reading
 * `state.labels.FEATURES` instead was a port regression: FEATURES carries the
 * 20 face-feature names ("Nasenbreite", "Lippendicke"), and the Makeup /
 * Overlay / Outfit panels were captioning body overlays "Nasenbreite" etc.
 */
export function overlayLabelMap(state: CreatorState): Record<string, string> | null {
  if (!state.overlayLabels) return null;
  const out: Record<string, string> = {};
  for (const [id, label] of Object.entries(state.overlayLabels)) {
    if (typeof label === 'string' && label.length > 0) out[id] = label;
  }
  return Object.keys(out).length > 0 ? out : null;
}
