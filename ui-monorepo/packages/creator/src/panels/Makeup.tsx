import * as React from 'react';
import { Caption, Row, type PanelNav } from './creatorTypes';

/* ====================================================================
 * Makeup.tsx — the Makeup panel.
 *
 * A heading and ten rows, each pushing 'overlay' with `{ id }`. The id
 * range 0..9 is HARDCODED — it does not come from `overlayLabels`. That
 * is what the original did (app.js:850-857) and what the extraction
 * agent confirmed: "This is the only panel whose id range is
 * hardcoded rather than data-driven."
 *
 * The body overlays 10..12 are reached through the Outfit panel, not
 * here. The button label falls back to 'Overlay ' + id when
 * `state.overlayLabels[id]` is absent — `overlayLabels` is in the same
 * class of "optional, sometimes missing" payload as `componentLabels`
 * / `propLabels` / `zoneLabels`, and buildPayload drops it (creatorTypes
 * note 1).
 *
 * Navigation is owned by the shell. The shell exposes a typed
 * `nav.pushPanel` so the panel never knows the discriminator; today
 * only 'overlay' leaves here, so the prop is narrowed.
 * ================================================================= */

/** 'Stil, Deckkraft und Farbe.' — verbatim from the original panelSubtitle. */
export const MAKEUP_SUBTITLE = 'Stil, Deckkraft und Farbe.';

/** app.js:851 — `for (let id = 0; id <= 9; id++)`. */
const MAKEUP_OVERLAY_IDS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] as const;

/** Same as the original: 'Stil, Deckkraft und Farbe.' on every row. */
const ROW_DESC = 'Stil, Deckkraft und Farbe.';

export interface MakeupProps {
  overlayLabels: Readonly<Record<string, string>> | null | undefined;
  nav: PanelNav;
}

export function MakeupPanel({ overlayLabels, nav }: MakeupProps) {
  return (
    <div className="flex flex-col gap-1.5 p-4">
      <Caption>Overlays</Caption>
      {MAKEUP_OVERLAY_IDS.map((id) => {
        // Verbatim German fallback. `labels[id] || ('Overlay ' + id)`
        // (app.js:852). The `.label ?? .description` form preserves
        // an empty string if the labels map has a key but no value.
        const label =
          overlayLabels && typeof overlayLabels[String(id)] === 'string'
            ? overlayLabels[String(id)]!
            : `Overlay ${id}`;
        return (
          <Row
            key={id}
            label={label}
            desc={ROW_DESC}
            onClick={() => nav.pushPanel('overlay', { id })}
          />
        );
      })}
    </div>
  );
}
