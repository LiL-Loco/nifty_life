import * as React from 'react';
import { cn } from '@nifty/ui';
import {
  Caption,
  List,
  creatorBridge,
  send,
  type ItemNames,
  type SlotOption,
  type SlotSelection,
} from './creatorTypes';

/* ====================================================================
 * Slot.tsx — wardrobe-group widgets and the slot panel.
 *
 * The cross-panel infrastructure (send, Caption, List, CreatorState,
 * Row, LabeledSlider, Overlay, ItemNames, …) lives in creatorTypes.tsx.
 * The wardrobe group only owns three things, and they all live here:
 *
 *   - SlotPicker — the drawable + texture picker used by Hair and Slot.
 *                  Outfit does not need it; it just navigates to the
 *                  Slot panel.
 *   - ColourPicker — the swatch grid used by Hair (primary/highlight)
 *                  and Overlay (active palette).
 *   - SlotPanel — the panel itself; a SlotPicker plus the lazy fetch.
 *
 * The lazy fetch is owned here because it is panel-local: each mount of
 * (kind, id) issues one `getItemNames`, and the answer comes back on
 * `creator:itemNames` filtered by (kind, id). The shell does not need to
 * know.
 * ================================================================= */

/* ============================================================ primitives */

/** What SlotPicker accepts as a kind, mirrored from creatorTypes. */
export type SlotKind = 'components' | 'props';

/**
 * A drawable picker, optionally stacked with a texture picker. Hair
 * passes `showTexture={false}` because the hairstyle catalogue has no
 * per-drawable textures to browse.
 */
export function SlotPicker({
  modellLabel,
  modelItems,
  modelIndex,
  onModelChange,
  textureLabel,
  textureItems,
  textureIndex,
  onTextureChange,
  showTexture,
}: {
  modellLabel: string;
  modelItems: readonly string[];
  modelIndex: number;
  onModelChange: (next: number) => void;
  textureLabel?: string;
  textureItems?: readonly string[];
  textureIndex?: number;
  onTextureChange?: (next: number) => void;
  /** Slot.tsx passes true; Hair.tsx passes false. */
  showTexture: boolean;
}) {
  return (
    <div className="flex flex-col gap-2">
      <Caption>{modellLabel}</Caption>
      <List label={modellLabel} items={modelItems as string[]} index={modelIndex} onChange={onModelChange} />

      {showTexture && textureItems && onTextureChange ? (
        <>
          <Caption>{textureLabel ?? 'Ausfuehrung'}</Caption>
          <List
            label={textureLabel ?? 'Ausfuehrung'}
            items={textureItems as string[]}
            index={textureIndex ?? 0}
            onChange={onTextureChange}
          />
        </>
      ) : null}
    </div>
  );
}

/**
 * A horizontal row of colour swatches with the active one highlighted.
 *
 * Loosened to `readonly number[]` rather than a four-tuple so it accepts
 * `state.palettes.HAIR_PALETTE` and `OVERLAY_PALETTES` as typed in
 * creatorTypes.tsx — both are `number[][]`, the upstream consequence of
 * Lua tables that have no tuple shape.
 */
export function ColourPicker({
  label,
  palette,
  index,
  onChange,
}: {
  label: string;
  palette: ReadonlyArray<readonly number[]>;
  index: number;
  onChange: (next: number) => void;
}) {
  if (palette.length === 0) {
    // The original silently fell through to no UI; surfacing the gap is
    // the only honest answer (see the OVERLAY_PALETTES gap in
    // creatorTypes.tsx and ADR-0026).
    return <Caption>Keine Farbpalette</Caption>;
  }
  const safeIndex = Math.max(0, Math.min(palette.length - 1, index));
  const active = palette[safeIndex];
  const previewBg = `rgba(${active[0]}, ${active[1]}, ${active[2]}, ${active[3] / 255})`;

  return (
    <div className="flex flex-col gap-2 rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-background)] p-3">
      <div className="flex items-center justify-between">
        <span className="text-sm font-semibold text-[var(--color-foreground)]">{label}</span>
        <span
          aria-hidden="true"
          className="h-6 w-6 rounded-full border-2 border-[#07080a] shadow-sm"
          style={{ background: previewBg }}
        />
      </div>
      <div className="flex flex-wrap gap-1.5">
        {palette.map((rgba, i) => (
          <button
            key={i}
            type="button"
            title={`Farbe ${i + 1}`}
            aria-label={`Farbe ${i + 1}`}
            aria-pressed={i === safeIndex}
            onClick={() => onChange(i)}
            className={cn(
              'h-7 w-7 rounded-md border-2 transition-transform',
              i === safeIndex
                ? 'scale-110 border-[var(--color-amber)] shadow'
                : 'border-[var(--color-border)] hover:border-[var(--color-amber)]',
            )}
            style={{
              background: `rgba(${rgba[0]}, ${rgba[1]}, ${rgba[2]}, ${rgba[3] / 255})`,
            }}
          />
        ))}
      </div>
    </div>
  );
}

/* ============================================================== panel */

/**
 * The props the shell passes to SlotPanel.
 *
 * The shell owns `state.itemNames` (the cross-panel cache). SlotPanel
 * accepts a SINGLE slice (`itemNames`) plus an `onFetchNames` callback
 * so the same hook works whether the shell picked up the push itself or
 * delegated it to the panel.
 *
 * `label` is the German display name for this slot
 * (`componentLabels[id]` or `propLabels[id]`, with the original
 * `'Slot N'` / `'Prop N'` fallback applied by the shell). The panel
 * itself does not need access to those maps.
 */
export interface SlotPanelProps {
  kind: SlotKind;
  id: number;
  selection: Readonly<Record<SlotKind, Readonly<Record<string, SlotSelection>>>>;
  slots: Readonly<Record<SlotKind, Readonly<Record<string, readonly SlotOption[]>>>>;
  /** The shell-supplied cache for this (kind, id). Null on first mount. */
  itemNames: ItemNames | null;
  /** German display label for this slot — `Slot N` / `Prop N` fallback included. */
  label: string;
  /** Triggered from the panel's mount effect. The shell decides what it does. */
  onFetchNames: () => void;
}

/**
 * The body of the slot picker.
 *
 * Faithful, deliberately:
 * - Only `slot[0]` is read. ALLOWED_COLLECTIONS contains more; the
 *   original hardcoded `slot[0]` so the rest are unreachable. See
 *   creatorTypes.tsx on SlotOption.
 * - The drawable clamp uses `Math.min(Math.max(0, ...), option.drawables - 1)`,
 *   matching `drawable = Math.min(Number(cur.drawable) || 0, option.drawables - 1)`.
 * - The texture count is floored at 1, matching `Math.max(1, option.textures) - 1`
 *   upstream in cl_creator.lua's slotOptions.
 *
 * Fixed on purpose:
 * - The drawable picker is OPTIMISTIC: `setSlot` does NOT refresh
 *   (cl_nui.lua:309-314), so we render from the optimistic value the
 *   user just picked. The original waited for the (never-arriving) echo
 *   and the picker visually stalled on every click.
 * - The texture is re-derived on every drawable change. The original
 *   kept it in `state.selection[kind][id].texture` only.
 */
export function SlotPanel({
  kind,
  id,
  selection,
  slots,
  itemNames,
  label,
  onFetchNames,
}: SlotPanelProps) {
  const slot = slots[kind][String(id)] ?? [];
  const option = slot[0];

  /* ---- lazy fetch: ask once per (kind, id) -------------------------- */

  React.useEffect(() => {
    onFetchNames();
    // Intentional: only kind/id belong in the dep list. `onFetchNames` is
    // expected to be stable; if it isn't, the shell has a bug worth
    // surfacing, not absorbing.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [kind, id]);

  /* ---- guard: slot has no option at all ---------------------------- */

  if (!option) {
    // app.js:985 — verbatim German string for an empty slot.
    return (
      <div className="flex flex-col gap-2 p-4">
        <Caption>Keine Stuecke verfuegbar.</Caption>
      </div>
    );
  }

  /* ---- selection: current drawable / texture, clamped ------------ */

  const cur = selection[kind][String(id)] ?? {
    collection: option.name,
    drawable: 0,
    texture: 0,
  };
  const drawable = Math.min(
    Math.max(0, Number(cur.drawable) || 0),
    Math.max(0, option.drawables - 1),
  );
  const textureCount = Math.max(1, option.textures);
  const texture = Math.min(
    Math.max(0, Number(cur.texture) || 0),
    textureCount - 1,
  );

  /* ---- lookup names from the cache -------------------------------- */

  const names = itemNames?.names ?? {};
  const nameFor = (d: number, t: number): string | null => {
    const byDrawable = names[String(d)];
    if (!byDrawable) return null;
    const found = byDrawable[String(t)];
    return typeof found === 'string' ? found : null;
  };

  const modelLabels: string[] = [];
  for (let d = 0; d < option.drawables; d++) {
    modelLabels.push(nameFor(d, texture) ?? `Modell ${d + 1}`);
  }
  const texLabels: string[] = [];
  for (let t = 0; t < textureCount; t++) {
    texLabels.push(nameFor(drawable, t) ?? `Ausfuehrung ${t + 1}`);
  }

  /* ---- handlers --------------------------------------------------- */

  const onPickDrawable = React.useCallback(
    (next: number) => {
      void send('setSlot', {
        kind,
        id,
        slot: { collection: option.name, drawable: next, texture },
      });
    },
    [kind, id, option.name, texture],
  );

  const onPickTexture = React.useCallback(
    (next: number) => {
      void send('setSlot', {
        kind,
        id,
        slot: { collection: option.name, drawable, texture: next },
      });
    },
    [kind, id, option.name, drawable],
  );

  /* ---- render ----------------------------------------------------- */

  return (
    <div className="flex flex-col gap-2 p-4">
      <Caption>{label}</Caption>
      <SlotPicker
        modellLabel="Modell"
        modelItems={modelLabels}
        modelIndex={drawable}
        onModelChange={onPickDrawable}
        textureLabel="Ausfuehrung"
        textureItems={texLabels}
        textureIndex={texture}
        onTextureChange={onPickTexture}
        showTexture
      />
    </div>
  );
}

/* ====================================================================
 * The creatorBridge subscription that wires `getItemNames` replies into
 * the slot panel.
 *
 * Exported separately so a shell that wants to centralise the cache can
 * import `subscribeItemNames` once instead of having the panel duplicate
 * the listener. Keeping it here also keeps the type-narrowing (filter by
 * `kind`+`id`) next to the only file that knows the cache key shape.
 * ================================================================= */

export interface ItemNamesEvent {
  kind: SlotKind;
  id: number;
  /** Latest known names for this (kind, id), or null on miss. */
  names: ItemNames | null;
}

/**
 * Listen for `creator:itemNames` and emit only the events whose
 * `(kind, id)` match the current slot. Returns the unsubscribe.
 */
export function subscribeItemNames(
  slot: { kind: SlotKind; id: number },
  handler: (event: ItemNamesEvent) => void,
): () => void {
  return creatorBridge.on('creator:itemNames', (data) => {
    if (!data || data.kind !== slot.kind || Number(data.id) !== slot.id) return;
    handler({
      kind: slot.kind,
      id: slot.id,
      names: data.names ?? null,
    });
  });
}

/* `Caption` is owned by creatorTypes.tsx. Hair and Overlay import it from
   HERE because this module is where the wardrobe group's widgets live; without
   this re-export their import resolves to a name this file does not export. */
export { Caption };
