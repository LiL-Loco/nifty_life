import * as React from 'react';
import { Slider } from '@nifty/ui';
import {
  Caption,
  List,
  send,
  type Overlay,
} from './creatorTypes';
import { ColourPicker } from './Slot';

/* ====================================================================
 * Overlay.tsx — the Stil + Deckkraft + Farbe panel.
 *
 * Reachable from Makeup (id 0..9) and Outfit (id 10..maxOverlay). The
 * same component handles every id — the panel does not know whether the
 * id is a face-paint or a body-paint, only which slot it points at.
 *
 * `setOverlay` carries the FULL overlay object, not a patch. cl_creator.lua's
 * setOverlay (line 1151-1161) REPLACES the stored entry rather than
 * patching it — so omitting the colourType field would erase it on the
 * next save. We always send the whole object, and we always copy the
 * live `overlay` values into the patch. This is the one wire-format
 * invariant the React port has to reproduce.
 *
 * THREE Lua-side defects shape what this component can render:
 *
 *   1. `OVERLAY_PALETTES` is an undefined global on the Lua side
 *      (cl_creator.lua reads it, nothing assigns it). Until that is
 *      fixed, `state.palettes.OVERLAY_PALETTES[id]` arrives as undefined
 *      and the colour section does not render. The Stil and Deckkraft
 *      controls still work.
 *   2. `swapOverlayPalette`'s paletteIndex is 1-based on the wire
 *      (cl_nui.lua:450-456), with index 0 reserved. The off-by-one lives
 *      at the boundary, inside this file.
 *   3. The colour section sets `colour` AND `secondColour` to the same
 *      index. The picker is single-channel; the second channel changes
 *      only via `swapOverlayPalette`, which only matters when the active
 *      palette has multiple colour channels (rare).
 * ================================================================= */

/** The default overlay when `state.face.overlays[String(id)]` is absent. */
const DEFAULT_OVERLAY: Overlay = {
  style: 0,
  opacity: 0,
  colourType: 1,
  colour: 0,
  secondColour: 0,
};

/** One entry of `state.palettes.OVERLAY_PALETTES[id]`. */
type PaletteEntry = readonly [number, string, ReadonlyArray<readonly number[]>];

export interface OverlayProps {
  /** `panel.payload.id`. */
  id: number;
  overlayLabels: Readonly<Record<string, string>> | null;
  /**
   * `state.labels.OVERLAY_STYLES[String(id)]`. The shell has already
   * narrowed the record to this id; index 0 is the off-slot.
   */
  overlayStyles: readonly string[] | null;
  /** `state.face.overlays` — the WHOLE map; one entry is read per id. */
  overlays: Readonly<Record<string, Overlay>>;
  /** `state.palettes.OVERLAY_PALETTES` — the WHOLE map; one entry per id. */
  palettes: Readonly<Record<string, ReadonlyArray<PaletteEntry>>>;
}

export function OverlayPanel({
  id,
  overlayLabels,
  overlayStyles,
  overlays,
  palettes,
}: OverlayProps) {
  /* ---- panel title (verbatim German fallback) ------------------ */

  const title =
    overlayLabels && typeof overlayLabels[String(id)] === 'string'
      ? overlayLabels[String(id)]!
      : `Overlay ${id}`;

  /* ---- active overlay, with the original's default --------------- */

  const active: Overlay = overlays?.[String(id)] ?? DEFAULT_OVERLAY;

  /* ---- styles list + active index ---------------------------------- */

  const styles = React.useMemo(() => buildStyles(overlayStyles), [overlayStyles]);

  // The list index is (style + 1) when the overlay is active (opacity > 0);
  // otherwise it sits on the literal "Keins" entry. Mirrors app.js:873.
  const styleIndex =
    active.opacity > 0.01
      ? Math.min(styles.length - 1, (active.style ?? 0) + 1)
      : 0;

  /* ---- handlers --------------------------------------------------- */

  const onPickStyle = React.useCallback(
    (next: number) => {
      const nextOverlay: Overlay =
        next === 0
          ? // Off-slot: copy the DEFAULT, not `active`. The original does this
            // (app.js:878) so a "Keins" click is the only way to clear an overlay
            // — sending the current state would not have the same effect because
            // style=0 alone without opacity=0 still keeps the entry "active".
            { ...DEFAULT_OVERLAY }
          : {
              ...active,
              style: next - 1,
              // matches `Math.max(cur.opacity || 0, 0.5)` in app.js:879
              opacity: Math.max(active.opacity || 0, 0.5),
            };
      void send('setOverlay', { id, overlay: nextOverlay });
    },
    [id, active],
  );

  const onOpacityChange = React.useCallback(
    (next: number) => {
      const nextOverlay: Overlay = {
        ...active,
        opacity: next / 100,
      };
      void send('setOverlay', { id, overlay: nextOverlay });
    },
    [id, active],
  );

  /* ---- palettes --------------------------------------------------- */

  const paletteList = palettes?.[String(id)] ?? [];
  const paletteCount = paletteList.length;

  // The active palette is the one whose colourType matches the overlay's,
  // falling back to the first. Mirrors app.js:900-901.
  const activePaletteIndex = (() => {
    if (paletteCount === 0) return -1;
    const found = paletteList.findIndex((p) => p[0] === (active.colourType || 1));
    return found >= 0 ? found : 0;
  })();
  const currentPalette: PaletteEntry | undefined =
    activePaletteIndex >= 0 ? paletteList[activePaletteIndex] : undefined;
  const currentPaletteRgba: readonly (readonly number[])[] =
    (currentPalette?.[2] as readonly (readonly number[])[] | undefined) ?? [];

  /* ---- palette swap ----------------------------------------------- */

  const paletteLabels =
    paletteCount > 1 ? paletteList.map((p) => p[1] || 'Palette') : [];
  const onSwapPalette = React.useCallback(
    (next: number) => {
      // paletteIndex is 1-based on the wire (cl_nui.lua:450-456); index 0
      // is reserved. The off-by-one lives at the boundary.
      void send('swapOverlayPalette', { id, paletteIndex: next + 1 });
    },
    [id],
  );

  /* ---- colour change --------------------------------------------- */

  const onColourChange = React.useCallback(
    (next: number) => {
      // app.js:914-918: change colour AND secondColour to the same index.
      // Two-channel colour is set via `swapOverlayPalette`, not here.
      const nextOverlay: Overlay = {
        ...active,
        colour: next,
        secondColour: next,
      };
      void send('setOverlay', { id, overlay: nextOverlay });
    },
    [id, active],
  );

  /* ---- render ----------------------------------------------------- */

  const opacityIndex = Math.round((active.opacity || 0) * 100);

  return (
    <div className="flex flex-col gap-3 p-4">
      <Caption>{title}</Caption>

      <Caption>Stil</Caption>
      <List label={title} items={styles} index={styleIndex} onChange={onPickStyle} />

      <Caption>Deckkraft</Caption>
      <div className="flex flex-col gap-1.5 rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-background)] p-3">
        <div className="flex items-center justify-between text-sm">
          <span className="font-semibold text-[var(--color-foreground)]">Deckkraft</span>
          <span className="text-[var(--color-muted-foreground)]">{opacityIndex} %</span>
        </div>
        <Slider
          value={[opacityIndex]}
          min={0}
          max={100}
          step={1}
          aria-label="Deckkraft"
          onValueChange={(v) => onOpacityChange(v[0])}
        />
      </div>

      {/* Farbpalette + Farbe: rendered only when palette data is on the
          wire. OVERLAY_PALETTES being an undefined-global Lua table means
          this whole block currently NEVER renders — that is the Lua bug,
          not a UI decision. The types do not pretend otherwise. */}
      {currentPalette && currentPaletteRgba.length > 0 ? (
        <>
          {paletteCount > 1 ? (
            <>
              <Caption>Farbpalette</Caption>
              <List
                label="Farbpalette"
                items={paletteLabels as string[]}
                index={Math.max(0, activePaletteIndex)}
                onChange={onSwapPalette}
              />
            </>
          ) : null}
          <Caption>Farbe</Caption>
          <ColourPicker
            label={currentPalette[1] || 'Farbe'}
            palette={currentPaletteRgba}
            index={Math.max(
              0,
              Math.min(currentPaletteRgba.length - 1, active.colour || 0),
            )}
            onChange={onColourChange}
          />
        </>
      ) : null}
    </div>
  );
}

/**
 * Build the rendered styles list.
 *
 * The wire list starts with the literal "Keins", THEN every entry from
 * `overlayStyles[1..]`. The original SKIPS index 0 of overlayStyles and
 * inserts its own "Keins" — duplicating the off-slot, but ensuring the
 * German word stays consistent if the labels table mutates.
 */
function buildStyles(overlayStyles: readonly string[] | null | undefined): string[] {
  const styles: string[] = ['Keins'];
  const realStyles = overlayStyles ?? [];
  for (let i = 1; i < realStyles.length; i++) {
    styles.push(realStyles[i] || `Stil ${i}`);
  }
  return styles;
}
