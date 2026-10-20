import * as React from 'react';
import { Button, cn } from '@nifty/ui';
import {
  ROW_CLASS,
  SECTION_CLASS,
  tattooBridge,
  zoneLabel,
  type TattooEntry,
  type TattoosByZonePush,
  type ZoneLabelMap,
} from './Tattoos';

/**
 * One body zone's tattoos (root -> tattoos -> tattooZone).
 *
 * Faithful, deliberately:
 * - 'Keins' / 'Alle Tattoos dieser Zone entfernen.' / 'Lade Tattoos...' /
 *   'Zone fehlt.' and the per-row label+description (`t.name || t.collection`
 *   over `t.collection`) are the original strings, character for character.
 * - A zone whose answer has not arrived shows the loading separator, and so
 *   does a zone that came back empty — which is what the original did, and
 *   which is unreachable in practice because GameData.tattooZones() only
 *   returns zones holding at least one tattoo for this ped.
 *
 * Fixed on purpose:
 * - `getTattoosByZone` fired from the render body, so it re-sent on every
 *   rebuild. It is one request per zoneId here.
 * - The push is filtered by zoneId before it is stored. The original wrote
 *   every reply into the shared `byZone` map without checking which zone it
 *   belonged to, which is only safe because one zone is on screen at a time.
 */

export interface TattooZoneProps {
  /** `panel.payload.zoneId`. Typed nullable because the original guarded it. */
  zoneId: number | null | undefined;
  /** The creator's `zoneLabels`; see the note on `ZoneLabelMap`. */
  zoneLabels?: ZoneLabelMap;
  /**
   * The tattoo currently applied to THIS zone, if the shell knows it.
   *
   * `face.tattoos` is dead on the JavaScript side — nothing in the old panel
   * ever read it — but Lua really does maintain it (cl_creator.lua:1237/1249)
   * and forwards it inside `face` on every refresh, so the selection can be
   * marked without touching the Lua side. Optional: when the caller passes
   * nothing the tiles render exactly as the original rendered them.
   */
  activeTattoo?: { collection: string; preset: number } | null;
}

export function TattooZone({ zoneId, zoneLabels, activeTattoo }: TattooZoneProps) {
  const [tattoos, setTattoos] = React.useState<TattooEntry[] | null>(null);

  // Subscribe BEFORE asking, for the same reason as in Tattoos: a reply that
  // lands before the listener exists is dropped, and this is a push, not a
  // response body.
  React.useEffect(
    () =>
      tattooBridge.on('creator:tattoosByZone', (d: TattoosByZonePush) => {
        // `zoneId` is echoed back as the REQUEST body, so it is the zone that
        // was asked for. A push for another zone is not ours to store.
        if (!d || Number(d.zoneId) !== zoneId) return;
        setTattoos(Array.isArray(d.tattoos) ? d.tattoos : []);
      }),
    [zoneId],
  );

  React.useEffect(() => {
    if (typeof zoneId !== 'number') return;
    setTattoos(null);
    void tattooBridge.call('getTattoosByZone', { zoneId });
  }, [zoneId]);

  // The original's `typeof zoneId !== 'number'` guard, kept: `payload.zoneId`
  // arrives from a nav stack, and a malformed payload used to render
  // 'Zone fehlt.' rather than throw on `state.zoneLabels[undefined]`.
  if (typeof zoneId !== 'number') {
    return <div className="text-sm text-[var(--color-muted-foreground)]">Zone fehlt.</div>;
  }

  const label = zoneLabel(zoneId, zoneLabels);

  return (
    <div className="flex flex-col gap-1.5">
      <Button
        variant="ghost"
        className={ROW_CLASS}
        onClick={() => {
          void tattooBridge.call('removeTattoo', { zoneId });
        }}
      >
        <span className="flex-1">
          Keins
          <span className="mt-0.5 block text-[11px] font-normal text-[var(--color-muted-foreground)]">
            Alle Tattoos dieser Zone entfernen.
          </span>
        </span>
      </Button>

      {tattoos && tattoos.length > 0 ? (
        <>
          <div className={SECTION_CLASS}>{label}</div>

          {/*
            A grid rather than the original's single column: a body zone runs to
            dozens of entries and one full-width row each meant a lot of
            scrolling to find a tattoo. The two strings per tile are unchanged —
            the name on top, the collection underneath.
          */}
          <div className="grid grid-cols-2 gap-1.5">
            {tattoos.map((t) => {
              const key = `${t.collection}:${t.preset}`;
              const isActive =
                activeTattoo != null &&
                activeTattoo.collection === t.collection &&
                Number(activeTattoo.preset) === Number(t.preset);

              return (
                <Button
                  key={key}
                  variant="ghost"
                  // Deliberately no chevron: these rows apply a tattoo rather
                  // than navigating, and a '›' on sixty tiles reads as a link
                  // farm. The active tile is marked instead.
                  className={cn(
                    ROW_CLASS,
                    'min-w-0',
                    isActive && 'border-[var(--color-amber)] bg-[var(--color-secondary)]',
                  )}
                  onClick={() => {
                    void tattooBridge.call('pickTattoo', {
                      zoneId,
                      collection: t.collection,
                      preset: t.preset,
                    });
                  }}
                >
                  <span className="flex-1">
                    <span className="block truncate">{t.name || t.collection}</span>
                    <span className="mt-0.5 block truncate text-[11px] font-normal text-[var(--color-muted-foreground)]">
                      {t.collection}
                    </span>
                  </span>
                </Button>
              );
            })}
          </div>
        </>
      ) : (
        <div className={SECTION_CLASS}>Lade Tattoos...</div>
      )}
    </div>
  );
}