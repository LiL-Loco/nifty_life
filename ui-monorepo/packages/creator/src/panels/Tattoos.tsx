import * as React from 'react';
import { Button, createBridge } from '@nifty/ui';

/**
 * Tattoos — the zone list (root -> tattoos -> tattooZone).
 *
 * WHAT IS PORTED AND WHAT IS FIXED
 *
 * Faithful, deliberately:
 * - The zone list, the 'Zone ' + id fallback and the 'Lade Zonen...' loading
 *   separator are the original strings, verbatim.
 * - The zone buttons navigate. They do not call Lua; the nav stack belongs to
 *   the shell, so this component reports the id upward.
 *
 * Fixed on purpose:
 * - `getTattooZones` fired from the BODY of the render function, so it re-fired
 *   on every single render — including every `creator:refresh` caused by an
 *   unrelated gesture elsewhere in the creator. It is one request per mount
 *   here, keyed on nothing, because the zone list does not vary.
 * - The data arrives as a PUSH, not in the fetch response: cl_nui.lua:459-463
 *   sends `creator:tattooZones` via SendNUIMessage and answers `cb({ok=true})`.
 *   The response body carries no zones at all.
 */

/* ------------------------------------------------------------------ the data */

/** One row of `GameData.tattoosByZone` (client/cl_gamedata.lua:319-325). */
export interface TattooEntry {
  /** File name of the tattoo overlay, e.g. 'mp2023_01_overlays'. */
  collection: string;
  /** Per-gender hash name, the key the game's data files actually store. */
  hashName: string;
  /** joaat(hashName) — this is what pickTattoo wants. */
  preset: number;
  /** `LocalizedName` from the data file; falls back to Name, then 'Tattoo'. */
  name: string;
  /** 'ZONE_HEAD' / 'ZONE_TORSO' / ... — a STRING in the data files, not an id. */
  zone: string;
}

/**
 * `zoneLabels` from the creator state.
 *
 * It is typed optional and every read falls back, because the field NEVER
 * arrives: getState computes `zoneLabels = ZONE_LABELS` (cl_creator.lua:1116)
 * and ZONE_LABELS is not assigned anywhere in the resources tree — same class of
 * gap as FACE_1D_GROUPS. buildPayload (cl_nui.lua:146-162) does not forward it
 * either. So the fallback below is the only label players have seen, and the
 * types must not pretend otherwise.
 */
export type ZoneLabelMap = Record<string, string> | null | undefined;

/** `SendNUIMessage({ action = 'creator:tattooZones', data = { zones = zones } })`. */
export interface TattooZonesPush {
  zones?: number[] | null;
}

/** `SendNUIMessage({ action = 'creator:tattoosByZone', data = { zoneId, tattoos } })`. */
export interface TattoosByZonePush {
  zoneId?: number;
  tattoos?: TattooEntry[] | null;
}

/**
 * The tattoos action map.
 *
 * `type`, not `interface`: only type aliases get the implicit index signature
 * that satisfies `createBridge`'s `ActionMap` constraint, and with this alias
 * `bridge.on` accepts these two strings and nothing else.
 */
type TattooActions = {
  'creator:tattooZones': (body: TattooZonesPush) => void;
  'creator:tattoosByZone': (body: TattoosByZonePush) => void;
};

/**
 * One bridge for the whole tattoos group, declared in the panel that opens the
 * group and imported by its child. Two instances would also work — `on` only
 * adds a window listener — but then the action list would be written twice, and
 * that list is the thing that turns a renamed push into a build failure.
 */
export const tattooBridge = createBridge<TattooActions>({
  received: ['creator:tattooZones', 'creator:tattoosByZone'],
});

/** The label the original produced: `state.zoneLabels[zoneId] || 'Zone ' + zoneId`. */
export function zoneLabel(zoneId: number, zoneLabels: ZoneLabelMap): string {
  const found = zoneLabels ? zoneLabels[String(zoneId)] : undefined;
  return typeof found === 'string' && found !== '' ? found : 'Zone ' + zoneId;
}

/* ------------------------------------------------------------- shared styling */

/** `.cr-separator` from ui/style.css:117-124, in the shared tokens. */
export const SECTION_CLASS =
  'mx-2 mt-3 mb-1 text-[10px] font-semibold uppercase tracking-[0.18em] text-[var(--color-muted-foreground)]';

/**
 * A full-width row, replacing the original's `button(label, desc, onClick)`
 * factory (.cr-btn in ui/style.css:127-185).
 *
 * The shared Button is a centred pill; every creator row is a left-aligned
 * full-width block with a description under the label. tailwind-merge resolves
 * each conflict in favour of this className, so the row reads like the old
 * panel without forking the component.
 */
export const ROW_CLASS =
  'h-auto w-full justify-start gap-3 whitespace-normal rounded-[var(--radius-panel)] border border-[var(--color-border)] px-4 py-3 text-left text-sm font-medium normal-case tracking-normal hover:border-[var(--color-amber)] hover:bg-[var(--color-secondary)]';

/** The '›' the original appended to every row (`opts.chevron !== false`). */
export const CHEVRON_CLASS =
  'shrink-0 text-lg leading-none text-[var(--color-muted-foreground)]';

/* ------------------------------------------------------------------ Tattoos */

export interface TattoosProps {
  /** The creator's `zoneLabels`. Optional because it never arrives; see above. */
  zoneLabels?: ZoneLabelMap;
  /** The shell pushes 'tattooZone' with `{ zoneId }`; navigation is not ours. */
  onOpenZone: (zoneId: number) => void;
}

export function Tattoos({ zoneLabels, onOpenZone }: TattoosProps) {
  // null = not answered yet, which is what the original's `state.tattoos.zones`
  // starts as and the only state in which 'Lade Zonen...' is honest.
  const [zones, setZones] = React.useState<number[] | null>(null);

  // Subscribe BEFORE asking. Effects run in declaration order, so the listener
  // is live by the time the round trip below can possibly answer — the race the
  // original lost by firing the fetch inside the render body.
  //
  // The payload is annotated by hand because `Bridge.on` types its handler
  // parameter as `any`: the action map above documents the shape but does not
  // enforce it at the call site.
  React.useEffect(
    () =>
      tattooBridge.on('creator:tattooZones', (d: TattooZonesPush) => {
        // `Array.isArray` rather than the original's truthiness test: Lua sends
        // `zones = tryCall('getTattooZones') or {}`, and an empty Lua table has
        // no JSON array/object distinction. The original stored whatever came
        // back and then ran `for (const zoneId of zones)` on it, which throws on
        // an object. An unrecognised shape becomes an empty list instead.
        const next = d && Array.isArray(d.zones) ? d.zones : [];
        setZones(next.filter((z): z is number => typeof z === 'number'));
      }),
    [],
  );

  React.useEffect(() => {
    // Once per mount. The original re-sent this on every render, which under
    // the old code meant every full rebuild re-requested the zone list.
    void tattooBridge.call('getTattooZones');
  }, []);

  return (
    <div className="flex flex-col gap-1.5">
      {zones === null ? (
        // Verbatim from the original renderTattoos.
        <div className={SECTION_CLASS}>Lade Zonen...</div>
      ) : null}

      {zones?.map((zoneId) => (
        <Button
          key={zoneId}
          variant="ghost"
          className={ROW_CLASS}
          onClick={() => onOpenZone(zoneId)}
        >
          <span className="flex-1">{zoneLabel(zoneId, zoneLabels)}</span>
          <span aria-hidden="true" className={CHEVRON_CLASS}>
            ›
          </span>
        </Button>
      ))}

      {/*
        An empty zone list renders nothing, exactly as the original did — with
        the one difference that it no longer throws first. GameData.tattooZones
        only returns zones that hold at least one tattoo for this ped, so the
        list is empty on a ped with no tattoo DLC. There is no German string in
        the original for that case and inventing one would be new copy, so the
        shell is the right place to decide what an empty panel should say.
      */}
    </div>
  );
}