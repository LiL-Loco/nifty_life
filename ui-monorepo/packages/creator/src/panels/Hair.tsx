import * as React from 'react';
import { Slider } from '@nifty/ui';
import {
  Caption,
  send,
  type CreatorState,
} from './creatorTypes';
import { ColourPicker, SlotPicker } from './Slot';

/* ====================================================================
 * Hair.tsx — the Haare panel.
 *
 * Drawable picker over `slots.components[2]` (slot 2 = hair, hardcoded
 * by the GTA freemode ped), two HAIR_PALETTE swatches for primary and
 * highlight, and a 0..100 opacity slider for the hairOverlay.
 *
 * Three details the port has to reproduce:
 *
 *   1. `state.face.hairOverlay` may be nil on a brand-new character — the
 *      original defaults its opacity to 1.0 (`(state.face.hairOverlay
 *      && state.face.hairOverlay.opacity) || 1.0`, app.js:837).
 *   2. `setHairOverlayOpacity` resolves the overlay preset on the Lua side
 *      if `hairOverlay` is nil, creating it with `opacity = 1.0`
 *      (cl_creator.lua:1174-1180). We do NOT need to send `collection`
 *      or `preset` — that materialises on first edit.
 *   3. `setSlot` does NOT refresh (cl_nui.lua:309-314 — every other
 *      mutating callback does). The picker is OPTIMISTIC: it renders
 *      from the value the player just picked, and the missing refresh
 *      does not matter because the next render IS what the player sees.
 *
 * Shared widgets (Caption, send, Slider) live in creatorTypes.tsx.
 * SlotPicker and ColourPicker live in Slot.tsx and are imported here.
 * ================================================================= */

export interface HairProps {
  state: Pick<CreatorState, 'slots' | 'selection' | 'palettes' | 'face'>;
}

/** 'Frisur und Haarfarbe.' — verbatim from the original panelSubtitle. */
export const HAIR_SUBTITLE = 'Frisur und Haarfarbe.';

/** 'Keine Frisuren geladen.' — verbatim from app.js:812. */
export const HAIR_EMPTY = 'Keine Frisuren geladen.';

export function HairPanel({ state }: HairProps) {
  const slots = state?.slots;
  const selection = state?.selection;
  const palettes = state?.palettes;
  const face = state?.face;

  /* ---- data: only slot[0] is reachable ------------------------- */

  const slot = slots?.components?.['2'] ?? [];
  const option = slot[0];

  /* ---- empty-state: matches the original's empty separator ----- */

  if (!option) {
    return (
      <div className="flex flex-col gap-2 p-4">
        <Caption>{HAIR_EMPTY}</Caption>
      </div>
    );
  }

  /* ---- selection: drawable, clamped --------------------------- */

  const cur = selection?.components?.['2'] ?? {
    collection: option.name,
    drawable: 0,
    texture: 0,
  };
  const drawable = Math.min(
    Math.max(0, Number(cur.drawable) || 0),
    Math.max(0, option.drawables - 1),
  );

  /* ---- labels: 'Frisur N' verbatim (no names cache for hair) -- */

  const modelLabels: string[] = [];
  for (let d = 0; d < option.drawables; d++) {
    // The hair catalogue has no per-drawable texture names — cl_creator.lua
    // does not forward a names cache for hair. Fallback matches app.js:817.
    modelLabels.push(`Frisur ${d + 1}`);
  }

  /* ---- handlers ----------------------------------------------- */

  const onPickFrisur = React.useCallback(
    (next: number) => {
      void send('setSlot', {
        kind: 'components',
        id: 2,
        // texture: 0 — hairstyle has no per-drawable texture selection.
        slot: { collection: option.name, drawable: next, texture: 0 },
      });
    },
    [option.name],
  );

  const onPickPrimary = React.useCallback((next: number) => {
    void send('setHairColour', { channel: 'primary', index: next });
  }, []);

  const onPickHighlight = React.useCallback((next: number) => {
    void send('setHairColour', { channel: 'highlight', index: next });
  }, []);

  /* ---- opacity: 0..100 slides, the wire value is index/100 ---- */

  const opacity = face?.hairOverlay?.opacity ?? 1.0;
  const opacityIndex = Math.round(opacity * 100);

  const onOpacityChange = React.useCallback((next: number) => {
    void send('setHairOverlayOpacity', { opacity: next / 100 });
  }, []);

  /* ---- palette indices, clamped --------------------------------- */

  const palette = palettes?.HAIR_PALETTE ?? [];
  const primary = Math.max(
    0,
    Math.min(Math.max(0, palette.length - 1), face?.hairColour?.primary ?? 0),
  );
  const highlight = Math.max(
    0,
    Math.min(Math.max(0, palette.length - 1), face?.hairColour?.highlight ?? 0),
  );

  /* ---- render ------------------------------------------------- */

  return (
    <div className="flex flex-col gap-3 p-4">
      <Caption>Modell</Caption>
      <SlotPicker
        modellLabel="Frisur"
        modelItems={modelLabels}
        modelIndex={drawable}
        onModelChange={onPickFrisur}
        showTexture={false}
      />

      <Caption>Hauptfarbe</Caption>
      <ColourPicker
        label="Hauptfarbe"
        palette={palette}
        index={primary}
        onChange={onPickPrimary}
      />

      <Caption>Straehnen</Caption>
      <ColourPicker
        label="Straehnen"
        palette={palette}
        index={highlight}
        onChange={onPickHighlight}
      />

      <Caption>Hair Fade</Caption>
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
    </div>
  );
}
