/**
 * Barrel for the creator's shared type set.
 *
 * The concrete interfaces live in `panels/creatorTypes.tsx` because the four
 * shared widgets (`Row`, `Caption`, `List`, `LabeledSlider`) and the
 * `creatorBridge` / `send` machinery are co-located with the type set they
 * shape. `types.ts` exists so a future module that needs `CreatorState` /
 * `SlotKind` / `PanelNav` can `import … from './types'` instead of reaching
 * into the panels subtree.
 *
 * NOTHING in this file is hand-authored — every export is a re-export.
 */
export type {
  CreatorState,
  CreatorOpen,
  CreatorRefresh,
  CreatorPanelKind,
  PanelNav,
  HeadBlend,
  FaceState,
  Overlay,
  SlotSelection,
  SlotOption,
  FaceBone,
  FaceGroup1D,
  FaceGroup2D,
  ItemNames,
  TattooEntry,
  LabelSet,
  Palettes,
} from './panels/creatorTypes';

export { creatorBridge, send } from './panels/creatorTypes';
