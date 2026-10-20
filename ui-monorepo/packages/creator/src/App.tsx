import * as React from 'react';
import { Button, ScrollArea } from '@nifty/ui';

import {
  creatorBridge,
  send,
  type CreatorState,
  type CreatorPanelKind,
  type PanelNav,
  type Overlay as OverlayShape,
} from './panels/creatorTypes';
import { Root, rootSubtitle } from './panels/Root';
import { Heritage } from './panels/Heritage';
import { Parents, parentsSummary } from './panels/Parents';
import { EyeColour } from './panels/EyeColour';
import { FaceFeatures } from './panels/FaceFeatures';
import { HairPanel, HAIR_SUBTITLE } from './panels/Hair';
import { MakeupPanel, MAKEUP_SUBTITLE } from './panels/Makeup';
import { OverlayPanel } from './panels/Overlay';
import { OutfitPanel, type SummaryKey, OUTFIT_SUBTITLE } from './panels/Outfit';
import { SlotPanel } from './panels/Slot';
import { Tattoos } from './panels/Tattoos';
import { TattooZone } from './panels/TattooZone';
import {
  applyOpen,
  applyRefresh,
  createEmptyState,
  overlayLabelMap,
  slotSummary,
  upsertItemNames,
  upsertTattoosByZone,
} from './state';

/**
 * The creator shell: one state, one stack, one bridge.
 *
 * WHY ONE useState AND NOT AN EXTERNAL STORE
 *
 * The vanilla version had one mutable `state` object that ~40 call sites wrote
 * to directly, and every mutation re-rendered the whole panel tree by hand.
 * React makes the equivalent correct: one immutable state, replaced or merged
 * wholesale, with no two components writing to the same shape. The panels read
 * from it and call `send(...)`, which is the same split the old code had —
 * state here, side effects through the bridge — except neither can drift from
 * the other without the type system objecting.
 *
 * WHY THERE IS NO BACK BUTTON IN THE PANELS
 *
 * `PanelNav` has `popPanel(): boolean` and `pushPanel(...)` and nothing else.
 * `popPanel` returns false at depth 1 precisely so the ESC handler can tell
 * "go back" from "close everything". The shell owns that. A panel that could
 * pop itself would need to know the depth, which is the one thing it must not
 * decide.
 *
 * WHY THE WHOLE SHELL IS ONE FILE
 *
 * The twelve panels are independent and one panel-deep in the dependency tree,
 * so a separate file per panel was free; the shell is the OPPOSITE shape — it
 * knows every panel and every dispatcher. Splitting it would require passing
 * the panel list across files for no gain. The shell is the file that has to
 * know about everything; everything else needs to know about the shell.
 */

/* --------------------------------------------------------------- panel stack */

/** A single entry on the navigation stack. */
interface Panel {
  kind: CreatorPanelKind;
  /** Slot id, overlay id, or tattoo zone id — for the three panels that need one. */
  arg?: number;
  /** The `kind` discriminator for SlotPanel: 'components' or 'props'. */
  slotKind?: 'components' | 'props';
}

/**
 * The five panels that want the head closeup. `updateSkinCamState` (app.js:160)
 * fires `showSkinCam` when the top panel changes between a member of this set
 * and anything else.
 */
const FACE_CAM_KINDS = new Set<CreatorPanelKind>([
  'heritage',
  'parents',
  'faceFeatures',
  'hair',
  'makeup',
]);

/** The panel chrome strings per top-of-stack. None of these are reworded. */
const NON_ROOT_SUBTITLE =
  'Aussehen - Name und Stammdaten stehen bereits fest.';
const TATTOOS_SUBTITLE = 'Tattoos pro Koerperzone.';
const FACEFEATURES_HINT = 'Ziehen, um das Gesicht zu formen.';

/* --------------------------------------------------------------- app shell */

export function App() {
  const [open, setOpen] = React.useState(false);
  const [state, setState] = React.useState<CreatorState>(() => createEmptyState());
  const [stack, setStack] = React.useState<Panel[]>([]);
  const [error, setError] = React.useState('');

  /* ---- the navigation object: the ONLY way panels enter/leave ----------- */

  const nav: PanelNav = React.useMemo(
    () => ({
      pushPanel: (kind, payload) => {
        const arg =
          payload && typeof payload.id === 'number' ? payload.id : undefined;
        const slotKind =
          payload && (payload.kind === 'components' || payload.kind === 'props')
            ? payload.kind
            : undefined;
        setStack((prev) => [
          ...prev,
          { kind, arg, slotKind } as Panel,
        ]);
      },
      popPanel: () => {
        // Returning a boolean is the contract; the ESC handler reads it to
        // decide close-on-false / pop-on-true.
        let did = false;
        setStack((prev) => {
          if (prev.length <= 1) return prev;
          did = true;
          return prev.slice(0, -1);
        });
        return did;
      },
    }),
    [],
  );

  const active = stack[stack.length - 1];

  /* ---- lua -> panel ---------------------------------------------------- */

  React.useEffect(() => {
    const offs = [
      creatorBridge.on('creator:open', (d) => {
        setState((s) => applyOpen(s, (d as Partial<CreatorState>) ?? {}));
        setStack([{ kind: 'root' }]);
        setError('');
        setOpen(true);
      }),
      creatorBridge.on('creator:refresh', (d) => {
        setState((s) => applyRefresh(s, (d as Partial<CreatorState>) ?? {}));
      }),
      creatorBridge.on('creator:close', () => {
        setOpen(false);
        setStack([]);
      }),
      creatorBridge.on('creator:error', (d: { message?: string }) => {
        setError(d?.message || 'Unbekannter Fehler.');
      }),
      creatorBridge.on('creator:faceBones', (d) => {
        // FaceFeatures owns the bones; just preserve a no-op record here so
        // the shape stays in sync.
        if (!d) return;
      }),
      creatorBridge.on('creator:itemNames', (d) => {
        if (
          !d ||
          typeof d.kind !== 'string' ||
          typeof d.id !== 'number' ||
          !d.names
        ) {
          return;
        }
        const entry = { kind: d.kind, id: d.id, names: d.names };
        setState((s) => ({ ...s, itemNames: upsertItemNames(s, entry) }));
      }),
      creatorBridge.on('creator:parentPortraits', (d) => {
        // captureParentPortrait is a stub returning ''. Parents.tsx deliberately
        // ignores this push, so the shell does too. See Parents.tsx note on
        // requestParentPortraits.
        if (!d) return;
      }),
      creatorBridge.on('creator:tattooZones', (d) => {
        const zones =
          d && Array.isArray((d as { zones?: unknown }).zones)
            ? ((d as { zones: unknown[] }).zones as number[]).filter(
                (z): z is number => typeof z === 'number',
              )
            : null;
        setState((s) => ({
          ...s,
          tattoos: { ...s.tattoos, zones },
        }));
      }),
      creatorBridge.on('creator:tattoosByZone', (d) => {
        if (
          !d ||
          typeof (d as { zoneId?: unknown }).zoneId !== 'number' ||
          !Array.isArray((d as { tattoos?: unknown }).tattoos)
        ) {
          return;
        }
        const payload = d as { zoneId: number; tattoos: unknown[] };
        const tattoos = payload.tattoos as never[];
        setState((s) => ({
          ...s,
          tattoos: upsertTattoosByZone(s.tattoos, payload.zoneId, tattoos as never),
        }));
      }),
    ];
    return () => offs.forEach((off) => off());
  }, []);

  /* ---- ESC + camera orbit (Q/E) -------------------------------------- */

  React.useEffect(() => {
    if (!open) return undefined;
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement | null)?.tagName || '';
      if (['INPUT', 'TEXTAREA', 'SELECT'].includes(tag)) return;

      if (e.key === 'Escape') {
        e.preventDefault();
        if (!nav.popPanel()) void send('closePanel', {});
        return;
      }
      if (e.key === 'q' || e.key === 'Q' || e.code === 'KeyQ') {
        e.preventDefault();
        void send('camYaw', { delta: -1 });
        return;
      }
      if (e.key === 'e' || e.key === 'E' || e.code === 'KeyE') {
        e.preventDefault();
        void send('camYaw', { delta: 1 });
        return;
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, nav]);

  /* ---- showSkinCam: re-fire on every active-panel change --------------- */

  const wantFaceCam =
    !!active && FACE_CAM_KINDS.has(active.kind);
  React.useEffect(() => {
    if (!open) return undefined;
    void send('showSkinCam', { kind: wantFaceCam ? 'face' : 'body' });
    return undefined;
  }, [open, wantFaceCam]);

  /* ---- face bones: only tick while the face panel is up ---------------- */

  const faceActive = active?.kind === 'faceFeatures';
  React.useEffect(() => {
    if (!open || !faceActive) {
      // Turn it off explicitly when we leave the panel — the cleanup didn't
      // run while open stayed true, and a stale thread would tick forever.
      if (open) void send('setFaceBonesActive', { active: false });
      return undefined;
    }
    void send('setFaceBonesActive', { active: true });
    return () => {
      void send('setFaceBonesActive', { active: false });
    };
  }, [open, faceActive]);

  if (!open) return null;

  /* ---- shell render ----------------------------------------------------- */

  const subtitle = subtitleFor(active?.kind, state);
  const showHint =
    !!active &&
    FACE_CAM_KINDS.has(active.kind) &&
    active.kind !== 'heritage';

  return (
    <div className="pointer-events-none fixed inset-0 flex justify-end">
      <aside className="pointer-events-auto flex h-full w-[460px] flex-col border-l border-[var(--color-border)] bg-[var(--color-background)]">
        <header className="flex items-start justify-between gap-3 border-b border-[var(--color-border)] px-5 py-4">
          <div className="min-w-0">
            <h1 className="text-base font-extrabold uppercase tracking-[0.06em]">
              Charaktererstellung
            </h1>
            <p className="mt-0.5 text-xs text-[var(--color-muted-foreground)]">
              {subtitle}
            </p>
          </div>
          <Button
            variant="ghost"
            size="icon"
            aria-label="Schliessen"
            onClick={() => void send('closePanel', {})}
          >
            &times;
          </Button>
        </header>

        {error ? (
          <p className="border-b border-[var(--color-border)] px-5 py-2 text-sm text-destructive">
            {error}
          </p>
        ) : null}

        <ScrollArea className="flex-1">
          <div className="flex flex-col gap-4 p-4">
            {showHint ? (
              <p className="text-xs text-[var(--color-muted-foreground)]">{FACEFEATURES_HINT}</p>
            ) : null}
            {active ? (
              <PanelFor active={active} state={state} nav={nav} />
            ) : null}
          </div>
        </ScrollArea>
      </aside>
    </div>
  );
}

/* ------------------------------------------------------------- subtitle */

/**
 * Verbatim per-panel subtitle, mirroring `panelSubtitle` (app.js:208).
 *
 * Every string here is a copy from the legacy `panelSubtitle` plus the
 * imported `parentsSummary`. They are NOT reworded, NOT "improved" and NOT
 * translated — the German UI text is the server's product.
 */
function subtitleFor(
  kind: CreatorPanelKind | undefined,
  state: CreatorState,
): string {
  if (!kind || kind === 'root') return rootSubtitle(state.modelIsUndecided);
  if (kind === 'parents') return parentsSummary(state.face.headBlend);
  if (kind === 'heritage' || kind === 'eyeColour')
    return NON_ROOT_SUBTITLE;
  if (kind === 'faceFeatures') return NON_ROOT_SUBTITLE;
  if (kind === 'hair') return HAIR_SUBTITLE;
  if (kind === 'makeup') return MAKEUP_SUBTITLE;
  if (kind === 'tattoos') return TATTOOS_SUBTITLE;
  if (kind === 'outfit') return OUTFIT_SUBTITLE;
  return NON_ROOT_SUBTITLE;
}

/* ------------------------------------------------------------- summaries */

/**
 * Compute the per-row description for the outfit panel.
 *
 * app.js:926 (slotSummary) returns the cached display name for the current
 * drawable/texture, or 'Modell N' when no cache has arrived yet. The wardrobe
 * panel passes this as `desc` on each row. Without it, every outfit row
 * displayed '–' forever.
 */
function outfitSummaries(state: CreatorState): Partial<Record<SummaryKey, string>> {
  const out: Partial<Record<SummaryKey, string>> = {};
  for (const kind of ['components', 'props'] as const) {
    const ids = state.selection[kind] ?? {};
    for (const id of Object.keys(ids)) {
      const numId = parseInt(id, 10);
      if (!Number.isFinite(numId)) continue;
      const key = `${kind}:${numId}` as SummaryKey;
      out[key] = slotSummary(state.selection, state.itemNames, kind, numId);
    }
  }
  return out;
}

/* --------------------------------------------------------- panel router */

/**
 * Each panel gets exactly the props it declares — no shared bag, no `as any`.
 *
 * The panels were written against different slices of state on purpose (Hair
 * needs the hair palette, Overlay needs one overlay by id, the Outfit needs the
 * per-row summaries), and a single `faceProps` spread would have made eight of
 * them silently wrong.
 */
function PanelFor({
  active,
  state,
  nav,
}: {
  active: Panel;
  state: CreatorState;
  nav: PanelNav;
}) {
  const overlayLabels = overlayLabelMap(state);
  const summaries = outfitSummaries(state);

  switch (active.kind) {
    case 'root':
      return <Root state={state} nav={nav} />;
    case 'heritage':
      return <Heritage nav={nav} />;
    case 'parents':
      return <Parents state={state} />;
    case 'eyeColour':
      return (
        <EyeColour
          eyeColour={state.face.eyeColour}
          eyeColourLabels={state.labels.EYE_COLOURS ?? null}
        />
      );
    case 'faceFeatures':
      return (
        <FaceFeatures
          features={state.face.features}
          groups2D={state.faceGroups.FACE_2D ?? null}
          groups1D={state.faceGroups.FACE_1D ?? null}
        />
      );
    case 'hair':
      return (
        <HairPanel
          state={
            {
              slots: state.slots,
              selection: state.selection,
              palettes: state.palettes,
              face: state.face,
            } as never
          }
        />
      );
    case 'makeup':
      return <MakeupPanel nav={nav} overlayLabels={overlayLabels} />;
    case 'overlay': {
      const id = active.arg ?? 0;
      const overlayEntry: OverlayShape | undefined = state.face.overlays[String(id)];
      const styles = (state.labels.OVERLAY_STYLES ?? {})[String(id)] ?? null;
      const palettes =
        (state.palettes.OVERLAY_PALETTES ?? {}) as unknown as Record<
          string,
          ReadonlyArray<readonly [number, string, readonly (readonly number[])[]]>
        >;
      return (
        <OverlayPanel
          id={id}
          overlayLabels={overlayLabels}
          overlayStyles={styles as readonly string[] | null}
          overlays={(state.face.overlays ?? {}) as Record<string, OverlayShape>}
          palettes={palettes}
        />
      );
    }
    case 'outfit':
      return (
        <OutfitPanel
          slots={state.slots as never}
          componentLabels={state.componentLabels ?? null}
          propLabels={state.propLabels ?? null}
          overlayLabels={overlayLabels}
          summaries={summaries}
          nav={nav}
        />
      );
    case 'slot': {
      const id = active.arg ?? 0;
      const kind = active.slotKind ?? 'components';
      const cacheKey: SummaryKey = `${kind}:${id}` as SummaryKey;
      const labels = kind === 'components' ? state.componentLabels : state.propLabels;
      const label = labels && labels[String(id)] ? labels[String(id)] : `${kind === 'components' ? 'Slot' : 'Prop'} ${id}`;
      return (
        <SlotPanel
          kind={kind}
          id={id}
          selection={state.selection as never}
          slots={state.slots as never}
          itemNames={state.itemNames?.[cacheKey] ?? null}
          label={label}
          onFetchNames={() => void send('getItemNames', { kind, id })}
        />
      );
    }
    case 'tattoos':
      return (
        <Tattoos
          zoneLabels={state.zoneLabels ?? null}
          onOpenZone={(zoneId: number) => nav.pushPanel('tattooZone', { id: zoneId })}
        />
      );
    case 'tattooZone':
      return (
        <TattooZone
          zoneId={active.arg ?? null}
          zoneLabels={state.zoneLabels ?? null}
        />
      );
    default:
      return null;
  }
}
