import * as React from 'react';
import { Caption, Row, type CreatorState, type PanelNav } from './creatorTypes';

/* ====================================================================
 * Outfit.tsx — the Outfit panel.
 *
 * Three lists of buttons:
 *
 *   Kleidung     — every component slot EXCEPT id 2 (hair lives in the
 *                  Haare category, app.js:948 hardcodes `if (id === 2) continue`).
 *   Accessoires  — every prop slot.
 *   Koerperfarbe — body overlays id 10..maxOverlay. maxOverlay is
 *                  `Object.keys(overlayLabels).length`, falling back to 12.
 *
 * Tapping a row navigates to either the slot picker (`kind`, `id`) or
 * the overlay picker (`id`). Navigation is owned by the shell — the
 * panel receives `nav` (a typed `PanelNav`) and forwards `pushPanel`.
 *
 * The summary line on each row is the slot's display name. The shell
 * pre-computes a `summaries` map keyed by `${kind}:${id}` (and
 * `overlays:${id}` for body overlays) from `slotSummary` (app.js:926).
 * Missing keys fall back to '–'.
 *
 * The shell also passes the LABEL maps directly — `componentLabels`,
 * `propLabels`, `overlayLabels` — all optional because buildPayload drops
 * them (creatorTypes note 1). The fallback 'Slot N' / 'Prop N' /
 * 'Overlay N' lives here because the shell cannot know the order of
 * display; it activates only when the maps are absent. The moment Lua
 * forwards them, the maps win.
 * ================================================================= */

/** app.js:214 — verbatim. */
export const OUTFIT_SUBTITLE = 'Kleidung, Accessoires und Koerperfarbe.';

/** app.js:966 — `Object.keys(overlayLabels).length || 12`. */
const OVERLAY_FALLBACK_MAX = 12;

/**
 * The shell-supplied cache key shape — `'components:3'`, `'props:0'`,
 * `'overlays:10'`. The same shape `slotSummary` (app.js:926) produced
 * dynamically for the kind/id case.
 */
export type SummaryKey = `${'components' | 'props' | 'overlays'}:${number}`;

export interface OutfitProps {
  slots: CreatorState['slots'];
  /** `state.componentLabels`. Optional — see creatorTypes note 1. */
  componentLabels: Readonly<Record<string, string>> | null;
  /** `state.propLabels`. Optional. */
  propLabels: Readonly<Record<string, string>> | null;
  /** `state.overlayLabels`. Optional. */
  overlayLabels: Readonly<Record<string, string>> | null;
  /**
   * Pre-computed summaries, keyed by `${kind}:${id}` (and
   * `overlays:${id}` for body overlays). Missing key means "no summary
   * yet"; the panel falls back to '–'.
   */
  summaries: Partial<Record<SummaryKey, string>>;
  /** Typed nav from the shell; pushed to 'slot' / 'overlay'. */
  nav: PanelNav;
}

/* ============================================================ helpers */

function sortedIds(map: Readonly<Record<string, unknown>>): number[] {
  const ids: number[] = [];
  for (const k of Object.keys(map)) {
    const n = parseInt(k, 10);
    if (Number.isFinite(n)) ids.push(n);
  }
  ids.sort((a, b) => a - b);
  return ids;
}

function labelFor(
  map: Readonly<Record<string, string>> | null,
  id: number,
  fallback: string,
): string {
  if (map) {
    const found = map[String(id)];
    if (typeof found === 'string' && found.length > 0) return found;
  }
  return fallback;
}

/* ============================================================ panel */

export function OutfitPanel({
  slots,
  componentLabels,
  propLabels,
  overlayLabels,
  summaries,
  nav,
}: OutfitProps) {
  /* ---- the three id lists ------------------------ */

  // Sort numerically — `Object.keys({3:'a'})` returns ['3']; both
  // numeric and string-id maps are handled, since the JSON wire has
  // numeric ids stringified.
  const compIds = sortedIds(slots?.components ?? {}).filter((id) => id !== 2);
  const propIds = sortedIds(slots?.props ?? {});

  // maxOverlay mirrors app.js:966:
  //   `const maxOverlay = (state.overlayLabels && Object.keys(state.overlayLabels).length) || 12;`
  const overlayLabelCount = overlayLabels ? Object.keys(overlayLabels).length : 0;
  const maxOverlay = overlayLabelCount > 0 ? overlayLabelCount : OVERLAY_FALLBACK_MAX;

  /* ---- render ----------------------------------- */

  return (
    <div className="flex flex-col gap-1.5 p-4">
      {compIds.length > 0 ? (
        <>
          <Caption>Kleidung</Caption>
          {compIds.map((id) => (
            <Row
              key={`components:${id}` as SummaryKey}
              label={labelFor(componentLabels, id, `Slot ${id}`)}
              desc={summaries[`components:${id}` as SummaryKey] ?? '–'}
              onClick={() => nav.pushPanel('slot', { kind: 'components', id })}
            />
          ))}
        </>
      ) : null}

      {propIds.length > 0 ? (
        <>
          <Caption>Accessoires</Caption>
          {propIds.map((id) => (
            <Row
              key={`props:${id}` as SummaryKey}
              label={labelFor(propLabels, id, `Prop ${id}`)}
              desc={summaries[`props:${id}` as SummaryKey] ?? '–'}
              onClick={() => nav.pushPanel('slot', { kind: 'props', id })}
            />
          ))}
        </>
      ) : null}

      {/* Koerperfarbe is always rendered, even when no summaries have
          arrived yet, so the heading is visible on a fresh character. */}
      <Caption>Koerperfarbe</Caption>
      {Array.from({ length: Math.max(0, maxOverlay - 10 + 1) }, (_, i) => {
        const id = 10 + i;
        return (
          <Row
            key={`overlays:${id}` as SummaryKey}
            label={labelFor(overlayLabels, id, `Overlay ${id}`)}
            desc={summaries[`overlays:${id}` as SummaryKey] ?? '–'}
            onClick={() => nav.pushPanel('overlay', { id })}
          />
        );
      })}
    </div>
  );
}
