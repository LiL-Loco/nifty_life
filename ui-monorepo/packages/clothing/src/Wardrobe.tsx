import * as React from 'react';
import { ScrollArea } from '@nifty/ui';
import {
  clothingBridge,
  pieceIdOf,
  send,
  type CharacterName,
  type Kind,
  type Outfit,
  type Piece,
  type RefreshData,
  type WardrobeOpen,
  type WardrobeSlots,
} from './contract';
import { PanelHeader, useChrome } from './chrome';
import { characterName, asList, pieceKey, slotKey } from './format';
import { isEditingText, useTimerRunner } from './hooks';
import { wardrobeSlotLabel } from './labels';
import { Caption, Row, TextField } from './widgets';

/**
 * The wardrobe screen: slots -> owned pieces, plus the outfit list.
 *
 * Six screens, no stack and no animation — the same shape the vanilla version
 * had, expressed as a reducer instead of a `switch` in `renderPanel()`.
 */

/**
 * How long a fetch may stay silent before the panel says so.
 *
 * Three of this panel's fetches can produce TOTAL silence, and the contract
 * says so explicitly: `getOwnedForSlot` sends `slot` where the server reads
 * `payload.slot_id`, and an unknown `kind` early-returns with no error reply
 * at all. Without a timeout, "broken" and "empty" look identical on screen —
 * which is how the whole first version of this panel shipped dead without
 * anyone noticing.
 */
const FETCH_TIMEOUT_MS = 4000;

/** Shown when a fetch went unanswered. The vanilla panels had no such path. */
const NO_REPLY = 'Keine Antwort vom Server.';

/* ------------------------------------------------------------------- state */

type Screen = 'root' | 'slot' | 'outfits' | 'outfit-actions' | 'rename' | 'save';

interface SlotRef {
  kind: Kind;
  id: number;
}

interface State {
  screen: Screen;
  character: CharacterName | null;
  slots: WardrobeSlots;
  /**
   * Keyed by kind, then by STRINGIFIED slot id: Lua writes numeric keys and
   * JSON turns them into strings, so a `Record<number, Piece[]>` lookup misses
   * silently under any index-signature checking.
   */
  owned: Record<Kind, Record<string, Piece[]>>;
  outfits: Outfit[];
  activeSlot: SlotRef | null;
  activeOutfit: Outfit | null;
  saveName: string;
  /** The slot whose fetch is still outstanding, or null. */
  loadingSlotKey: string | null;
  outfitsLoading: boolean;
}

type Action =
  | { type: 'owned'; kind: Kind; slot: string; items: Piece[] }
  | { type: 'outfits'; list: Outfit[] }
  | { type: 'selectSlot'; slot: SlotRef }
  | { type: 'slotLoading'; key: string | null }
  | { type: 'slotTimeout'; key: string }
  | { type: 'outfitsLoading'; value: boolean }
  | { type: 'openOutfits' }
  | { type: 'openSave' }
  | { type: 'openRename' }
  | { type: 'selectOutfit'; outfit: Outfit }
  | { type: 'backToOutfits' }
  | { type: 'setName'; name: string }
  | { type: 'home' };

const EMPTY_SLOTS: WardrobeSlots = { components: [], props: [] };

function initialState(open: WardrobeOpen): State {
  return {
    screen: 'root',
    character: open.extra.character ?? null,
    slots: open.extra.slots ?? EMPTY_SLOTS,
    owned: { component: {}, prop: {} },
    outfits: [],
    activeSlot: null,
    activeOutfit: null,
    saveName: '',
    loadingSlotKey: null,
    outfitsLoading: false,
  };
}

/**
 * `owned` is a PATCH for one (kind, slot), not a replacement of the whole map.
 *
 * The vanilla version did `state.owned = data.owned`, so opening a second slot
 * silently emptied the first and the wardrobe appeared to lose your clothes.
 */
function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'owned': {
      const { kind, slot, items } = action;
      const next: State = {
        ...state,
        owned: {
          ...state.owned,
          [kind]: { ...state.owned[kind], [slot]: items },
        },
      };
      if (state.loadingSlotKey === slotKey(kind, Number(slot))) {
        next.loadingSlotKey = null;
      }
      return next;
    }

    case 'outfits':
      return { ...state, outfits: action.list, outfitsLoading: false };

    case 'selectSlot':
      return { ...state, screen: 'slot', activeSlot: action.slot };

    case 'slotLoading':
      return { ...state, loadingSlotKey: action.key };

    case 'slotTimeout':
      return state.loadingSlotKey === action.key
        ? { ...state, loadingSlotKey: null }
        : state;

    case 'outfitsLoading':
      return { ...state, outfitsLoading: action.value };

    case 'openOutfits':
      return { ...state, screen: 'outfits' };

    case 'openSave':
      return { ...state, screen: 'save', saveName: '' };

    case 'openRename':
      return { ...state, screen: 'rename', saveName: state.activeOutfit?.name ?? '' };

    case 'selectOutfit':
      return { ...state, screen: 'outfit-actions', activeOutfit: action.outfit };

    case 'backToOutfits':
      return { ...state, screen: 'outfits', activeOutfit: null };

    case 'setName':
      return { ...state, saveName: action.name };

    case 'home':
      return { ...state, screen: 'root', activeSlot: null, activeOutfit: null };
  }
}

/* -------------------------------------------------------------- the screen */

export function Wardrobe({ open }: { open: WardrobeOpen }) {
  const [state, dispatch] = React.useReducer(reducer, open, initialState);
  const { close, toast } = useChrome();
  const arm = useTimerRunner();
  const name = characterName(state.character);

  /* ---- Lua -> panel -------------------------------------------------- */

  React.useEffect(
    () =>
      clothingBridge.on('clothing:refresh', (data: RefreshData) => {
        if (!data) return;
        // Both keys go through `asList`: Lua writes `list or {}`, and an empty
        // table is not reliably encoded as `[]`. See format.ts.
        if (data.outfits) dispatch({ type: 'outfits', list: asList(data.outfits) });

        const patch = data.owned;
        if (!patch) return;
        for (const kind of ['component', 'prop'] as const) {
          const bySlot = patch[kind];
          if (!bySlot) continue;
          for (const slot of Object.keys(bySlot)) {
            dispatch({ type: 'owned', kind, slot, items: asList(bySlot[slot]) });
          }
        }
      }),
    [],
  );

  /* ---- outstanding requests ------------------------------------------ */

  const slotKeyLoading = state.loadingSlotKey;
  React.useEffect(() => {
    if (!slotKeyLoading) return;
    return arm(() => {
      dispatch({ type: 'slotTimeout', key: slotKeyLoading });
      toast(NO_REPLY, true);
    }, FETCH_TIMEOUT_MS);
  }, [slotKeyLoading, arm, toast]);

  const outfitsLoading = state.outfitsLoading;
  React.useEffect(() => {
    if (!outfitsLoading) return;
    return arm(() => {
      dispatch({ type: 'outfitsLoading', value: false });
      toast(NO_REPLY, true);
    }, FETCH_TIMEOUT_MS);
  }, [outfitsLoading, arm, toast]);

  /* ---- actions ------------------------------------------------------- */

  const openSlot = React.useCallback(
    (slot: SlotRef) => {
      dispatch({ type: 'selectSlot', slot });
      dispatch({ type: 'slotLoading', key: slotKey(slot.kind, slot.id) });
      void send('getOwnedForSlot', { kind: slot.kind, id: slot.id });
    },
    [],
  );

  const openOutfits = React.useCallback(() => {
    // Ref counter. `getOutfits` stacks a one-shot Lua handler for
    // 'nifty:client:outfitList' on EVERY call, so re-entering the screen while
    // a request is in flight would pile handlers onto one event name.
    if (state.outfitsLoading) return;
    dispatch({ type: 'openOutfits' });
    dispatch({ type: 'outfitsLoading', value: true });
    void send('getOutfits', {});
  }, [state.outfitsLoading]);

  const rename = React.useCallback(() => {
    const target = state.activeOutfit;
    // The UUID goes through verbatim. Lua's `tostring(tonumber(data.id) or '')`
    // turns it into '' anyway — see contract.ts note (d/e) — but this side is
    // correct, so the rename starts working the day that tonumber is dropped.
    if (target) void send('renameOutfit', { id: target.id, name: state.saveName });
    dispatch({ type: 'backToOutfits' });
  }, [state.activeOutfit, state.saveName]);

  const removeOutfit = React.useCallback(() => {
    const target = state.activeOutfit;
    if (!target) return;
    void send('deleteOutfit', { id: target.id });
    // No local removal on purpose. The server does NOT re-broadcast the outfit
    // list after a delete, so dropping the row here would show a delete that
    // did not happen. The row survives until the next `getOutfits`, which is
    // the truth this panel is able to know.
    dispatch({ type: 'backToOutfits' });
  }, [state.activeOutfit]);

  /* ---- Escape -------------------------------------------------------- */

  const screen = state.screen;
  React.useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      // Same rule as the vanilla panels: an Escape inside a text field only
      // leaves the field, it never closes the wardrobe behind the dialog.
      if (isEditingText(event.target)) {
        event.target.blur();
        return;
      }
      if (screen === 'root') close();
      else dispatch({ type: 'home' });
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [screen, close]);

  /* ---- screens ------------------------------------------------------- */

  const goHome = React.useCallback(() => dispatch({ type: 'home' }), []);
  const goBackToOutfits = React.useCallback(() => dispatch({ type: 'backToOutfits' }), []);

  const renderRoot = () => {
    const components = [...state.slots.components].sort((a, b) => a - b);
    const props = [...state.slots.props].sort((a, b) => a - b);

    return (
      <>
        {components.length > 0 ? (
          <>
            <Caption>Kleidung</Caption>
            {components.map((id) => (
              <Row
                key={slotKey('component', id)}
                label={wardrobeSlotLabel('component', id)}
                desc={`Slot ${id}`}
                onClick={() => openSlot({ kind: 'component', id })}
              />
            ))}
          </>
        ) : null}

        {props.length > 0 ? (
          <>
            <Caption>Accessoires</Caption>
            {props.map((id) => (
              <Row
                key={slotKey('prop', id)}
                label={wardrobeSlotLabel('prop', id)}
                desc={`Prop ${id}`}
                onClick={() => openSlot({ kind: 'prop', id })}
              />
            ))}
          </>
        ) : null}

        <Caption>Outfits</Caption>
        <Row label="Outfits ansehen" onClick={openOutfits} />
        <Row
          label="Outfit speichern"
          desc="Aktuelles Outfit unter Name ablegen."
          onClick={() => dispatch({ type: 'openSave' })}
        />
      </>
    );
  };

  const renderSlot = () => {
    const active = state.activeSlot;
    if (!active) return renderRoot();

    const pieces = state.owned[active.kind][String(active.id)] ?? [];
    const waiting = state.loadingSlotKey === slotKey(active.kind, active.id);

    return (
      <>
        <Row label="< Zurueck" chevron={false} onClick={goHome} />
        <Caption>{wardrobeSlotLabel(active.kind, active.id)}</Caption>
        <Row
          label="Ablegen"
          desc="Slot leeren."
          // DEAD ENDPOINT: `nifty:server:clothingUnequip` has no handler in
          // this repo. Kept wired and visible rather than hidden, because a
          // missing Lua export is a bug report, not a UI decision.
          onClick={() => void send('unequip', { kind: active.kind, id: active.id })}
        />

        {waiting ? <Caption>Lade ...</Caption> : null}

        {!waiting && pieces.length === 0 ? <Caption>Keine Stuecke.</Caption> : null}

        {pieces.map((piece) => (
          <Row
            key={pieceKey(piece)}
            // Lua always fills `name`, so the old `('Stueck ' + p.id)`
            // fallback — which rendered "Stueck undefined", because Piece has
            // no id — never actually fired. The drawable is the honest
            // fallback for the day it does.
            label={piece.name || `Stueck ${piece.drawable}`}
            desc={piece.collection}
            // Cannot succeed: the server handler needs a full `appearance`
            // table that only Lua can build. See contract.ts note (a).
            onClick={() =>
              void send('equip', {
                kind: active.kind,
                id: active.id,
                pieceId: pieceIdOf(piece),
              })
            }
          />
        ))}
      </>
    );
  };

  const renderOutfits = () => {
    const { outfits, outfitsLoading: loading } = state;

    return (
      <>
        <Row label="< Zurueck" chevron={false} onClick={goHome} />
        <Caption>Outfits</Caption>

        {loading ? <Caption>Lade ...</Caption> : null}
        {!loading && outfits.length === 0 ? <Caption>Keine Outfits gespeichert.</Caption> : null}

        {outfits.map((outfit) => (
          <Row
            key={outfit.id}
            label={outfit.name}
            desc="Klicken fuer Aktionen"
            onClick={() => dispatch({ type: 'selectOutfit', outfit })}
          />
        ))}
      </>
    );
  };

  const renderOutfitActions = () => {
    const target = state.activeOutfit;
    if (!target) return renderOutfits();

    return (
      <>
        <Row label="< Zurueck" chevron={false} onClick={goBackToOutfits} />
        <Caption>{target.name}</Caption>
        <Row
          label="Anziehen"
          desc="Outfit jetzt tragen."
          onClick={() => void send('applyOutfit', { id: target.id })}
        />
        <Row
          label="Umbenennen"
          desc="Namen aendern."
          onClick={() => dispatch({ type: 'openRename' })}
        />
        <Row
          label="Loeschen"
          desc="Outfit entgueltig entfernen."
          variant="danger"
          onClick={removeOutfit}
        />
      </>
    );
  };

  const renderRename = () => (
    <>
      <Row label="< Abbrechen" chevron={false} onClick={goBackToOutfits} />
      <Caption>Outfit umbenennen</Caption>
      <TextField
        placeholder="Neuer Name"
        value={state.saveName}
        onChange={(event) => dispatch({ type: 'setName', name: event.target.value })}
        onKeyDown={(event) => {
          if (event.key === 'Enter') rename();
        }}
      />
      <Row label="Speichern" variant="primary" chevron={false} onClick={rename} />
    </>
  );

  const renderSave = () => (
    <>
      <Row label="< Zurueck" chevron={false} onClick={goHome} />
      <Caption>Outfit speichern</Caption>
      <TextField
        placeholder="Name des Outfits"
        value={state.saveName}
        onChange={(event) => dispatch({ type: 'setName', name: event.target.value })}
        onKeyDown={(event) => {
          if (event.key === 'Enter') void send('saveOutfit', { name: state.saveName });
        }}
      />
      {/* No navigation on save, same as before: the server never answers this
          one (see contract.ts note (c)), so leaving the dialog open is the
          only honest state to be in. */}
      <Row
        label="Speichern"
        variant="primary"
        chevron={false}
        onClick={() => void send('saveOutfit', { name: state.saveName })}
      />
    </>
  );

  const body = (() => {
    switch (state.screen) {
      case 'slot':
        return renderSlot();
      case 'outfits':
        return renderOutfits();
      case 'outfit-actions':
        return renderOutfitActions();
      case 'rename':
        return renderRename();
      case 'save':
        return renderSave();
      default:
        return renderRoot();
    }
  })();

  return (
    <>
      <PanelHeader
        title="WARDROBE"
        subtitle="Kleidung, Accessoires und Outfits."
        aside={name}
        onClose={close}
      />
      <ScrollArea className="min-h-0 flex-1">
        <div className="flex flex-col gap-1.5 p-4">{body}</div>
      </ScrollArea>
    </>
  );
}