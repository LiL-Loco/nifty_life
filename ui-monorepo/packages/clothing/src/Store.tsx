import * as React from 'react';
import { ScrollArea } from '@nifty/ui';
import {
  clothingBridge,
  send,
  type Kind,
  type PurchaseReply,
  type StoreItem,
  type StoreListData,
  type StoreOpen,
} from './contract';
import { PanelHeader, useChrome } from './chrome';
import { asList, money, slotKey } from './format';
import { isEditingText, useTimerRunner } from './hooks';
import { STORE_COMPONENT_SLOTS, STORE_PROP_SLOTS, storeRootLabel, storeSlotLabel } from './labels';
import { Caption, Row } from './widgets';

/**
 * The store screen: the browsable catalogue for the shop the player is in.
 *
 * Two screens — the slot picker and the per-slot price list — plus a toast for
 * the purchase result.
 */

const FETCH_TIMEOUT_MS = 4000;

/** Shown when a purchase produced no `purchaseResult` push within the window. */
const NO_REPLY = 'Keine Antwort vom Server.';

/* ------------------------------------------------------------------- state */

type Screen = 'root' | 'slot';

interface SlotRef {
  kind: Kind;
  id: number;
}

interface State {
  screen: Screen;
  activeSlot: SlotRef | null;
  /** Cache key `kind:id` -> items. A slot keeps its list while you browse on. */
  items: Record<string, StoreItem[]>;
  loadingKey: string | null;
  /** True between firing a purchase and its (possible) reply. */
  purchasePending: boolean;
}

type Action =
  | { type: 'selectSlot'; slot: SlotRef }
  | { type: 'storeList'; kind: Kind; id: number; items: StoreItem[] }
  | { type: 'loading'; key: string | null }
  | { type: 'listTimeout'; key: string }
  | { type: 'purchasePending'; value: boolean }
  | { type: 'home' };

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'selectSlot':
      return { ...state, screen: 'slot', activeSlot: action.slot };

    case 'storeList': {
      // `storeList` is a PERMANENT Lua handler and is not keyed by request, so
      // a reply for a slot the player already left can land at any moment. The
      // active slot is the only one allowed to update the view.
      const active = state.activeSlot;
      if (!active || active.kind !== action.kind || active.id !== action.id) return state;
      const key = slotKey(action.kind, action.id);
      return {
        ...state,
        items: { ...state.items, [key]: action.items },
        loadingKey: state.loadingKey === key ? null : state.loadingKey,
      };
    }

    case 'loading':
      return { ...state, loadingKey: action.key };

    case 'listTimeout':
      return state.loadingKey === action.key ? { ...state, loadingKey: null } : state;

    case 'purchasePending':
      return { ...state, purchasePending: action.value };

    case 'home':
      return { ...state, screen: 'root', activeSlot: null };
  }
}

/* -------------------------------------------------------------- the screen */

export function Store({ open }: { open: StoreOpen }) {
  // The store screen needs nothing from the open push to start empty, so the
  // initialiser ignores its argument entirely and the component stays pure
  // state. (The wardrobe DOES need `slots` / `character`, so it seeds from
  // its prop instead.)
  const [state, dispatch] = React.useReducer(reducer, null, (): State => ({
    screen: 'root',
    activeSlot: null,
    items: {},
    loadingKey: null,
    purchasePending: false,
  }));
  const { close, toast } = useChrome();
  const arm = useTimerRunner();

  /* ---- Lua -> panel -------------------------------------------------- */

  React.useEffect(
    () => clothingBridge.on('storeList', (data: StoreListData) => {
      if (!data || !data.kind) return;
      dispatch({ type: 'storeList', kind: data.kind, id: data.id, items: asList(data.items) });
    }),
    [],
  );

  React.useEffect(
    () =>
      clothingBridge.on('purchaseResult', (data: PurchaseReply) => {
        if (!data) return;
        if (data.ok) {
          toast(`Gekauft fuer $${money(data.price)}`);
          // The vanilla version closed the shop 800 ms after a successful buy.
          arm(() => void send('closePanel', {}), 800);
          return;
        }
        toast(`Kauf fehlgeschlagen: ${data.reason || 'unbekannt'}`, true);
      }),
    [toast, arm],
  );

  /* ---- outstanding requests ------------------------------------------ */

  const loadingKey = state.loadingKey;
  React.useEffect(() => {
    if (!loadingKey) return;
    return arm(() => {
      dispatch({ type: 'listTimeout', key: loadingKey });
      toast(NO_REPLY, true);
    }, FETCH_TIMEOUT_MS);
  }, [loadingKey, arm, toast]);

  const purchasePending = state.purchasePending;
  React.useEffect(() => {
    if (!purchasePending) return;
    return arm(() => {
      dispatch({ type: 'purchasePending', value: false });
      // While Lua hardcodes `collection = ''` the server rejects every buy
      // before it replies, so this is what a click actually produces today.
      // The wording is the vanilla failure toast with the same fallback it
      // already used for an empty reason.
      toast('Kauf fehlgeschlagen: unbekannt', true);
    }, FETCH_TIMEOUT_MS);
  }, [purchasePending, arm, toast]);

  /* ---- actions ------------------------------------------------------- */

  const openSlot = React.useCallback((slot: SlotRef) => {
    dispatch({ type: 'selectSlot', slot });
    dispatch({ type: 'loading', key: slotKey(slot.kind, slot.id) });
    void send('getStoreListForSlot', { kind: slot.kind, id: slot.id });
  }, []);

  const purchase = React.useCallback(
    (slot: SlotRef, item: StoreItem) => {
      dispatch({ type: 'purchasePending', value: true });
      void send('purchaseItem', {
        kind: slot.kind,
        slot_id: slot.id,
        drawable: item.drawable,
        texture: item.texture,
        // Not on the wire yet: `Price.listForSlot` only SELECTs drawable,
        // texture, name and price. Lua hardcodes `collection = ''` today, so
        // this is forwarded for the day both sides grow the field and is inert
        // until then. See contract.ts note (f).
        collection: item.collection ?? '',
      });
    },
    [],
  );

  /* ---- Escape -------------------------------------------------------- */

  const screen = state.screen;
  React.useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
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

  const renderRoot = () => (
    <>
      <Caption>Komponenten</Caption>
      {STORE_COMPONENT_SLOTS.map((id) => (
        <Row
          key={slotKey('component', id)}
          label={storeRootLabel('component', id)}
          desc="Klicken zum Kaufen."
          onClick={() => openSlot({ kind: 'component', id })}
        />
      ))}

      {STORE_PROP_SLOTS.length > 0 ? (
        <>
          <Caption>Accessoires</Caption>
          {STORE_PROP_SLOTS.map((id) => (
            <Row
              key={slotKey('prop', id)}
              label={storeRootLabel('prop', id)}
              desc="Klicken zum Kaufen."
              onClick={() => openSlot({ kind: 'prop', id })}
            />
          ))}
        </>
      ) : null}
    </>
  );

  const renderSlot = () => {
    const active = state.activeSlot;
    if (!active) return renderRoot();

    const key = slotKey(active.kind, active.id);
    const items = state.items[key];
    const waiting = state.loadingKey === key;

    return (
      <>
        <Row label="< Zurueck" chevron={false} onClick={goHome} />
        <Caption>{storeSlotLabel(active.kind, active.id)}</Caption>

        {waiting && !items ? <Caption>Lade ...</Caption> : null}

        {!waiting && items && items.length === 0 ? (
          <Caption>Aktuell nichts im Angebot.</Caption>
        ) : null}

        {items
          ? items.map((item) => (
              <Row
                key={`${item.drawable}|${item.texture}`}
                label={`${item.name || `Stueck #${item.drawable}`}   -$${money(item.price)}`}
                desc="Kauf und ziehe dieses Stueck direkt an."
                disabled={purchasePending}
                onClick={() => purchase(active, item)}
              />
            ))
          : null}
      </>
    );
  };

  const body = state.screen === 'slot' ? renderSlot() : renderRoot();

  // The store id is informational only — Lua never reads it back, the server
  // picks the price list itself. `manual` is what the /niftyclotheshop command
  // and the F7 key pass, and it is not a shop anyone can name.
  const rawStoreId = open.extra.storeId;
  const storeId =
    rawStoreId === undefined || rawStoreId === null || rawStoreId === 'manual'
      ? null
      : String(rawStoreId);

  return (
    <>
      <PanelHeader
        title="KLAMOTTENLADEN"
        subtitle="Kleidung, Accessoires und Preise."
        aside={storeId}
        onClose={close}
      />
      <ScrollArea className="min-h-0 flex-1">
        <div className="flex flex-col gap-1.5 p-4">{body}</div>
      </ScrollArea>
    </>
  );
}