import * as React from 'react';
import { Grid1DH, Grid1DV, Grid2D, DragDot, cn } from '@nifty/ui';
import {
  Caption,
  creatorBridge,
  send,
  type FaceBone,
  type FaceGroup1D,
  type FaceGroup2D,
} from './creatorTypes';

/**
 * Gesichtszuege — the face-feature panel and the 30 Hz face-bone overlay.
 *
 * ---------------------------------------------------------------------------
 * WHERE THE 1,440 LISTENERS PER SECOND WERE
 * ---------------------------------------------------------------------------
 *
 * `renderFaceBones` ran on every `creator:faceBones` push (30 Hz) and for each
 * of 24 bones registered a `mousemove` and a `mouseup` pair on `window`:
 *
 *     window.addEventListener('mousemove', ...)   // per bone, per push
 *     window.addEventListener('mouseup',   ...)   // per bone, per push
 *
 * Nothing ever removed them. 24 bones x 2 x 30 pushes = 1,440 registrations a
 * second, and the old build threw the dot elements away on the next push, so
 * every surviving listener kept computing against a detached node forever. The
 * face panel also died functionally on top of that: the dots were drawn at
 * `x * window.innerWidth` (see BELOW), i.e. up to ~100x the screen width.
 *
 * Here there is ONE `mousemove`/`mouseup` pair for the whole overlay, attached
 * on mount and detached on unmount, and only one drag can be live at a time —
 * a second dot cannot be dragged before the first is released, so there is no
 * per-dot state to keep. The three grid surfaces come from @nifty/ui and have
 * the same shape of fix.
 *
 * ---------------------------------------------------------------------------
 * THE COORDINATE BUG, FIXED RATHER THAN TRANSCRIBED
 * ---------------------------------------------------------------------------
 *
 * `projectFaceBones` (cl_creator.lua:1321) feeds these dots from
 * `GetScreenCoordFromWorldCoord`, which returns PIXELS. The old renderer
 * multiplied them by `window.innerWidth` / `window.innerHeight`:
 *
 *     dot.style.left = (b.x * w) + 'px'    // w === window.innerWidth
 *
 * which is a no-op times the viewport — every dot landed far off screen. These
 * dots are positioned `left: x` / `top: y` in the same pixel space the mouse
 * reports `clientX` / `clientY` in, which is also the space the 200 px drag
 * sweep below is measured in.
 *
 * A coord of exactly (0, 0) is what the native returns for a point that is NOT
 * on screen, so those bones are skipped rather than stacked in the top-left
 * corner.
 *
 * ---------------------------------------------------------------------------
 * WHAT THE PANEL STILL CANNOT SHOW, AND WHY THAT IS NOT A PORT REGRESSION
 * ---------------------------------------------------------------------------
 *
 * `faceGroups` is `{ FACE_1D = FACE_1D_GROUPS, FACE_2D = FACE_2D_GROUPS }`
 * (cl_creator.lua:1105). Both names are UNDEFINED GLOBALS: nothing in the
 * resource assigns them, so both are nil, and a Lua table constructor with nil
 * values is an EMPTY table. On top of that, `buildPayload` (cl_nui.lua:149)
 * does not forward `faceGroups` at all.
 *
 * So `groups2D` and `groups1D` arrive empty and this panel renders its two
 * section headings and nothing else — exactly what the vanilla build rendered.
 * The types in creatorTypes.tsx are written against the element shapes the old
 * renderer's property accesses imply, so the panel is correct the moment Lua
 * sends real groups. That is a one-line-per-key Lua fix in `buildPayload`; this
 * package is not allowed to make it (hard constraint), and faking placeholder
 * groups here would invent 20 face features nobody wired to the engine.
 *
 * ---------------------------------------------------------------------------
 * THE TWO CONVENTIONS THAT COULD NOT BOTH BE RIGHT
 * ---------------------------------------------------------------------------
 *
 * FACE_1D uses `(left, right)` as the horizontal axis pair. FACE_2D was called
 * as `grid2D(title, g.top, g.right, g.bottom, g.left, ...)`, i.e. with
 * topL=top, topR=right, bottomL=bottom, bottomR=left — which puts the `top`
 * string on the top-left and the `left` string on the bottom-right, i.e. swaps
 * the vertical and horizontal axis labels. Only one of the two can describe the
 * data, and the two were never seen at once because FACE_2D has always been
 * empty.
 *
 * DECISION: a FACE_2D group carries FOUR axis strings — `left`/`right` for the
 * xId axis and `top`/`bottom` for the yId axis, the same convention FACE_1D
 * uses for the pair it has. So the 2D pad renders TWO axis rows beneath it
 * (`left ... right`, then `top ... bottom`) instead of four corner labels that
 * cannot be placed without inventing a pairing. The degraded 1D fallback below
 * already used exactly this convention (`(left, right)` for x, `(top, bottom)`
 * for y), so the 2D and 1D forms of the same group now agree.
 *
 * SECOND DECISION: when BOTH axes of a 2D group are pinned at an extreme, the
 * group renders nothing. There is no position to show and no gesture that could
 * move it, and the alternatives need a German label that does not exist yet in
 * any source file. It is the only way a group can vanish.
 *
 * THIRD: the vertical half of a degraded group uses the VERTICAL widget. The
 * old fallback edited a yId feature with a horizontal track carrying the labels
 * `top`/`bottom` — you dragged right to move something up. Grid1DV exists in
 * @nifty/ui for exactly this, so the y axis gets it.
 */

export interface FaceFeaturesProps {
  /**
   * `state.face.features`: engine -1..1, keyed by the STRINGIFIED feature id
   * because Lua writes `face.features[tostring(id)]`. Sparse — a missing entry
   * means 0, exactly like the old `|| 0`.
   */
  features?: Record<string, number> | null;
  /** `state.faceGroups.FACE_2D`. */
  groups2D?: readonly FaceGroup2D[] | null;
  /** `state.faceGroups.FACE_1D`. */
  groups1D?: readonly FaceGroup1D[] | null;
}

/* ------------------------------------------------------------- conversions */

/**
 * Normalised 0..1 -> engine -1..1, snapped to 0.01.
 *
 * The snap is `Math.floor(v * 100 + 0.5) / 100`, copied exactly.
 *
 * ONE deliberate difference from app.js: the old first line was
 * `(posX || 0.5) * 2 - 1`, and `0 || 0.5` is `0.5`. A drag to the far LEFT of
 * any face slider therefore left the feature at 0 (neutral) instead of -1, so
 * the left half of all twenty features could never reach its extreme. Only a
 * genuinely absent value defaults to 0.5 here; every other input, 0 included,
 * produces the same number as before.
 */
export function toFeature(pos: number | null | undefined): number {
  const p = pos == null ? 0.5 : pos;
  return Math.floor((p * 2 - 1) * 100 + 0.5) / 100;
}

/** Engine -1..1 -> normalised 0..1. Copied exactly, falsy guard and all. */
export function fromFeature(v: number | null | undefined): number {
  return v == null ? 0.5 : (v + 1) / 2;
}

/**
 * "This feature is pinned at an extreme." A FACE_2D group whose axes are
 * binary degrades to 1D widgets, because the 2D pad cannot express a pinned
 * axis. Never called with a missing value: `featureValue` already mapped that
 * to 0, which is NOT binary.
 */
export function isBinary(v: number | null | undefined): boolean {
  return v == null || v <= -0.99 || v >= 0.99;
}

/** Engine values live in -1..1; the native already clamps, this is the belt. */
function clampFeature(v: number): number {
  return Math.max(-1, Math.min(1, v));
}

/**
 * Lua writes `face.features[tostring(id)]`, so the key is a STRING even though
 * the id is a number. A missing entry is 0 — the old `|| 0`, and deliberately
 * not `isBinary`'s null case, because a fresh face is all zeros and a fresh
 * face must render every widget.
 */
function featureValue(features: Record<string, number>, id: number): number {
  const raw = features[String(id)];
  return typeof raw === 'number' && isFinite(raw) ? raw : 0;
}

/** Percentages are rendered exactly as the old widgets did: `42 %`, `42 / 58`. */
function percent(p: number): string {
  return (p * 100).toFixed(0) + ' %';
}

/**
 * The same number as a CSS length. `percent()` is for TEXT — "42 %" is not a
 * valid width, and a fill that silently fails to apply looks like a broken
 * widget rather than a wrong string.
 */
function percentCss(p: number): string {
  return (p * 100).toFixed(0) + '%';
}

/* ------------------------------------------------------- stable empty refs */

/** Module-level so a missing payload does not produce a new array per render. */
const NO_FEATURES: Record<string, number> = {};
const NO_GROUPS_2D: readonly FaceGroup2D[] = [];
const NO_GROUPS_1D: readonly FaceGroup1D[] = [];
const NO_BONES: readonly FaceBone[] = [];

/* ----------------------------------------------------------- widget chrome */

function WidgetFrame({ children }: { children: React.ReactNode }) {
  return (
    <div className="rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-background)] p-4">
      {children}
    </div>
  );
}

function WidgetHeading({ label, value }: { label: string; value: string }) {
  return (
    <div className="mb-3 flex items-baseline justify-between gap-2">
      <span className="truncate text-[11px] tracking-[0.12em] text-[var(--color-muted-foreground)] uppercase">
        {label}
      </span>
      <span className="shrink-0 font-mono text-xs text-[var(--color-amber)] tabular-nums">
        {value}
      </span>
    </div>
  );
}

/**
 * The two axis strings of a group, spread across the width (horizontal axis) or
 * stacked top to bottom (vertical axis). This is the `.cr-grid__ends` row.
 */
function AxisEnds({
  from,
  to,
  orientation = 'horizontal',
}: {
  from?: string;
  to?: string;
  orientation?: 'horizontal' | 'vertical';
}) {
  return (
    <div
      className={cn(
        'mt-1.5 flex gap-2 text-[11px] text-[var(--color-muted-foreground)]',
        orientation === 'horizontal'
          ? 'justify-between'
          : 'h-full flex-col justify-between',
      )}
    >
      <span className="truncate">{from || ''}</span>
      <span className="truncate text-right">{to || ''}</span>
    </div>
  );
}

/* -------------------------------------------------------------- 1D widgets */

/** Horizontal feature axis: a dot on a track, `left` at one end, `right` the other. */
function FeatureAxis1DH({
  label,
  left,
  right,
  pos,
  onChange,
}: {
  label: string;
  left?: string;
  right?: string;
  pos: number;
  onChange: (p: number) => void;
}) {
  return (
    <WidgetFrame>
      <WidgetHeading label={label} value={percent(pos)} />
      <Grid1DH ariaLabel={label} onDrag={(p) => onChange(p.x)}>
        <div
          className="absolute inset-y-0 left-0 rounded-full bg-[var(--color-amber)]/25"
          style={{ width: percentCss(pos) }}
        />
        <DragDot p={{ x: pos, y: 0.5 }} />
      </Grid1DH>
      <AxisEnds from={left} to={right} />
    </WidgetFrame>
  );
}

/**
 * Vertical feature axis: the same widget rotated, for the yId half of a group
 * whose other axis is pinned. The track is 160 px tall because the dot needs
 * room to travel; the axis strings are stacked beside it, as
 * `.cr-grid-1d-v__ends` did.
 */
function FeatureAxis1DV({
  label,
  top,
  bottom,
  pos,
  onChange,
}: {
  label: string;
  top?: string;
  bottom?: string;
  pos: number;
  onChange: (p: number) => void;
}) {
  return (
    <WidgetFrame>
      <WidgetHeading label={label} value={percent(pos)} />
      <div className="flex gap-3">
        <div className="h-[160px] flex justify-center">
          <Grid1DV ariaLabel={label} onDrag={(p) => onChange(p.y)}>
            <div
              className="absolute inset-x-0 top-0 rounded-full bg-[var(--color-amber)]/25"
              style={{ height: percentCss(pos) }}
            />
            <DragDot p={{ x: 0.5, y: pos }} />
          </Grid1DV>
        </div>
        <AxisEnds from={top} to={bottom} orientation="vertical" />
      </div>
    </WidgetFrame>
  );
}

/* -------------------------------------------------------------- 2D widget */

/**
 * One FACE_2D group. Both axes free -> the 2D pad. Exactly one axis pinned ->
 * that axis degrades to its own 1D widget. Both pinned -> nothing.
 */
function FaceGroup2DWidget({
  group,
  features,
  onFeature,
}: {
  group: FaceGroup2D;
  features: Record<string, number>;
  onFeature: (id: number, value: number) => void;
}) {
  const xv = featureValue(features, group.xId);
  const yv = featureValue(features, group.yId);
  const pinnedX = isBinary(xv);
  const pinnedY = isBinary(yv);
  const label = group.title || '';

  if (!pinnedX && !pinnedY) {
    const posX = fromFeature(xv);
    const posY = fromFeature(yv);
    return (
      <WidgetFrame>
        <WidgetHeading
          label={label}
          value={(posX * 100).toFixed(0) + ' / ' + (posY * 100).toFixed(0)}
        />
        <div className="h-[200px]">
          <Grid2D
            ariaLabel={label}
            // ONE pointer move, TWO setFeature calls, x then y — the exact
            // order the old onChange used, and the reason a 2D drag doubles the
            // NUI traffic of a 1D one.
            onDrag={(p) => {
              onFeature(group.xId, toFeature(p.x));
              onFeature(group.yId, toFeature(p.y));
            }}
          >
            <DragDot p={{ x: posX, y: posY }} />
          </Grid2D>
        </div>
        <AxisEnds from={group.left} to={group.right} />
        <AxisEnds from={group.top} to={group.bottom} />
      </WidgetFrame>
    );
  }

  if (pinnedX && pinnedY) {
    // Both axes at an extreme: no position to show, no gesture that could move
    // it. See the DECISION note in the file header.
    return null;
  }

  return pinnedX ? (
    <FeatureAxis1DV
      label={label}
      top={group.top}
      bottom={group.bottom}
      pos={fromFeature(yv)}
      onChange={(p) => onFeature(group.yId, toFeature(p))}
    />
  ) : (
    <FeatureAxis1DH
      label={label}
      left={group.left}
      right={group.right}
      pos={fromFeature(xv)}
      onChange={(p) => onFeature(group.xId, toFeature(p))}
    />
  );
}

/* ------------------------------------------------------------------ panel */

/**
 * The Gesichtszuege panel body.
 *
 * Props are the three slices of state it reads, and nothing else — Lua owns the
 * values. Every drag step posts `setFeature`; the engine value comes back
 * through `creator:refresh` and down the props again, which is what makes the
 * dot follow the pointer instead of the widget carrying its own `cur` in a
 * closure. That is also what makes a mid-drag re-render harmless: there is no
 * closure to lose its `dragging` flag in.
 */
export function FaceFeatures({
  features,
  groups2D,
  groups1D,
}: FaceFeaturesProps) {
  const g2 = groups2D == null ? NO_GROUPS_2D : groups2D;
  const g1 = groups1D == null ? NO_GROUPS_1D : groups1D;
  const f = features == null ? NO_FEATURES : features;

  const onFeature = React.useCallback((id: number, value: number) => {
    void send('setFeature', { id, value });
  }, []);

  return (
    <>
      <FaceBoneOverlay features={f} />

      <Caption>2D Merkmale</Caption>
      <div className="flex flex-col gap-2">
        {g2.map((g, i) => (
          <FaceGroup2DWidget
            key={g.xId + ':' + g.yId + ':' + i}
            group={g}
            features={f}
            onFeature={onFeature}
          />
        ))}
      </div>

      <Caption>1D Merkmale</Caption>
      <div className="flex flex-col gap-2">
        {g1.map((g, i) => (
          <FeatureAxis1DH
            key={g.id + ':' + i}
            label={g.title || ''}
            left={g.left}
            right={g.right}
            pos={fromFeature(featureValue(f, g.id))}
            onChange={(p) => onFeature(g.id, toFeature(p))}
          />
        ))}
      </div>
    </>
  );
}

/* ------------------------------------------------------- face-bone overlay */

/** How many pixels of drag cover the full -1..1 sweep of one feature. */
const BONE_DRAG_RANGE_PX = 200;

/** bone -> the feature index it edits, and on which axis. */
interface BoneAxes {
  x?: number;
  y?: number;
}

/**
 * The 24 bones of `FACE_BONE_NAMES` (cl_creator.lua:48) mapped to a face
 * feature index by DOMINANT drag axis. Copied from app.js:527 verbatim.
 *
 * The long comment above that table in app.js lists SetPedFaceFeature indices
 * 0..19 with German names, and it disagrees with this map in places (it calls
 * index 4 "Augenbrauen-Hoehe" while the map sends 4/5 as the x/y pair of the
 * brow bones, which is what Labels.FEATURES index 6/7 — Brauenhoehe /
 * Brauentiefe — actually describes). The map is the one that was running, so
 * the map is the one that is copied.
 */
const BONE_FEATURE_MAP: Record<string, BoneAxes> = {
  skel_l_cheek: { x: 6 },
  skel_r_cheek: { x: 6 },
  skel_l_eyeball: { y: 7 },
  skel_r_eyeball: { y: 7 },
  skel_l_lip_lower_corner: { x: 8 },
  skel_r_lip_lower_corner: { x: 8 },
  skel_l_eyebrow_01: { x: 4, y: 5 },
  skel_l_eyebrow_02: { x: 4, y: 5 },
  skel_l_eyebrow_03: { x: 4, y: 5 },
  skel_r_eyebrow_01: { x: 4, y: 5 },
  skel_r_eyebrow_02: { x: 4, y: 5 },
  skel_r_eyebrow_03: { x: 4, y: 5 },
  skel_l_nose_01: { y: 1 },
  skel_l_nose_02: { y: 1 },
  skel_r_nose_01: { y: 1 },
  skel_r_nose_02: { y: 1 },
  skel_l_jawline_root: { x: 14, y: 15 },
  skel_r_jawline_root: { x: 14, y: 15 },
  skel_l_chin_01: { x: 18, y: 17 },
  skel_l_chin_02: { x: 18, y: 17 },
  skel_l_chin_03: { x: 18, y: 17 },
  skel_r_chin_01: { x: 18, y: 17 },
  skel_r_chin_02: { x: 18, y: 17 },
  skel_r_chin_03: { x: 18, y: 17 },
};

/**
 * Which feature index a bone edits for a drag on the given axis. Single-axis
 * bones fall through to their one key; a bone with no key at all is null.
 */
function boneFeatureId(axes: BoneAxes, horizontal: boolean): number | null {
  const id = horizontal
    ? axes.x != null
      ? axes.x
      : axes.y
    : axes.y != null
      ? axes.y
      : axes.x;
  return typeof id === 'number' ? id : null;
}

/** One live drag. At most one exists; releasing the mouse clears the ref. */
interface BoneDrag {
  name: string;
  axes: BoneAxes;
  startX: number;
  startY: number;
  /** The axis was chosen from the first non-zero delta and then pinned. */
  horizontal: boolean;
  /** The feature's value when the drag began, read from Lua's state. */
  startValue: number;
  /** Null until the first move picks an axis. */
  id: number | null;
  value: number;
}

/**
 * The gold dots over the ped's face, driven by `creator:faceBones` at 30 Hz.
 *
 * Mounting this overlay is what turns the Lua projection thread on, so the
 * panel gets its 24 dots exactly while the player is shaping their face and
 * not one tick longer.
 *
 * It keeps its own bone state so the 30 Hz push re-renders 24 dots and nothing
 * else — the widgets above do not move at 30 Hz.
 *
 * NOTE: this element is `position: fixed`, so it must not be mounted inside an
 * ancestor with a `transform`, `filter` or `will-change`, which would become
 * its containing block and offset every dot by the panel's own position.
 */
export function FaceBoneOverlay({
  features,
}: {
  features: Record<string, number>;
}) {
  const [bones, setBones] = React.useState<readonly FaceBone[]>(NO_BONES);
  const [draggingName, setDraggingName] = React.useState<string | null>(null);
  const drag = React.useRef<BoneDrag | null>(null);

  // The window listeners below are registered once, so they must not close over
  // a `features` snapshot from the render that happened to mount them.
  const featuresRef = React.useRef(features);
  featuresRef.current = features;

  /* ---- Lua -> panel -------------------------------------------------- */

  React.useEffect(() => {
    // Register the listener BEFORE asking for the ticks, so no push lands in
    // the gap between the two.
    const off = creatorBridge.on('creator:faceBones', (data) => {
      setBones(data && Array.isArray(data.bones) ? data.bones : NO_BONES);
    });
    void send('setFaceBonesActive', { active: true });
    return () => {
      off();
      void send('setFaceBonesActive', { active: false });
    };
  }, []);

  /* ---- drag ---------------------------------------------------------- */

  // ONE listener pair for all 24 dots, attached for the overlay's lifetime. A
  // dot cannot be dragged while another one is, so there is nothing to keep per
  // element — that is the whole difference from the old code, which registered a
  // fresh pair on every 30 Hz push.
  React.useEffect(() => {
    const move = (e: MouseEvent) => {
      const d = drag.current;
      if (!d) return;

      if (d.id === null) {
        // No axis picked yet: pick it from the first movement that has one.
        const rawX = (e.clientX - d.startX) / BONE_DRAG_RANGE_PX;
        const rawY = (e.clientY - d.startY) / BONE_DRAG_RANGE_PX;
        if (rawX === 0 && rawY === 0) return;
        const horizontal = Math.abs(rawX) > Math.abs(rawY);
        const id = boneFeatureId(d.axes, horizontal);
        if (id === null) return;
        d.horizontal = horizontal;
        d.id = id;
        // Nothing has been written yet, so the current value is still the value
        // the drag started from.
        d.startValue = featureValue(featuresRef.current, id);
      }

      e.preventDefault();
      const delta = d.horizontal
        ? (e.clientX - d.startX) / BONE_DRAG_RANGE_PX
        : (e.clientY - d.startY) / BONE_DRAG_RANGE_PX;
      // ABSOLUTE value, sent on release — the same contract as the old
      // `pendingValue`, and the reason one drag produces exactly one write.
      d.value = clampFeature(d.startValue + delta);
    };

    const up = () => {
      const d = drag.current;
      drag.current = null;
      setDraggingName(null);
      // A click with no movement never chose an axis, so it writes nothing.
      if (!d || d.id === null) return;
      void send('setFeature', { id: d.id, value: d.value });
    };

    window.addEventListener('mousemove', move);
    window.addEventListener('mouseup', up);
    return () => {
      window.removeEventListener('mousemove', move);
      window.removeEventListener('mouseup', up);
    };
  }, []);

  const onDotMouseDown = React.useCallback(
    (e: React.MouseEvent<HTMLDivElement>, bone: FaceBone) => {
      const axes = BONE_FEATURE_MAP[bone.name];
      if (!axes) return;
      e.preventDefault();
      e.stopPropagation();
      drag.current = {
        name: bone.name,
        axes,
        startX: e.clientX,
        startY: e.clientY,
        horizontal: false,
        startValue: 0,
        id: null,
        value: 0,
      };
      setDraggingName(bone.name);
    },
    [],
  );

  /* ---- render -------------------------------------------------------- */

  return (
    <div className="pointer-events-none fixed inset-0 z-[5]">
      {bones.map((b, i) => {
        if (!BONE_FEATURE_MAP[b.name]) return null;
        if (typeof b.x !== 'number' || typeof b.y !== 'number') return null;
        if (!isFinite(b.x) || !isFinite(b.y)) return null;
        // GetScreenCoordFromWorldCoord answers (0, 0) for a point that is not on
        // screen; drawing those would pile the whole skeleton into the
        // top-left corner.
        if (b.x === 0 && b.y === 0) return null;

        const active = draggingName === b.name;
        return (
          <div
            key={b.name + ':' + i}
            // PIXELS, in the same client space the drag is measured in.
            style={{ left: b.x, top: b.y }}
            onMouseDown={(e) => onDotMouseDown(e, b)}
            className={cn(
              'pointer-events-auto absolute h-4 w-4 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-[#07080a] shadow select-none',
              active
                ? 'scale-125 cursor-grabbing bg-[var(--color-amber)] shadow-[0_0_16px_rgba(240,165,58,0.9)]'
                : 'cursor-grab bg-[var(--color-amber)] shadow-[0_0_8px_rgba(240,165,58,0.5)] hover:scale-125',
            )}
          />
        );
      })}
    </div>
  );
}