import * as React from 'react';
import {
  Button,
  Card,
  ScrollArea,
  Separator,
  ToggleGroup,
  ToggleGroupItem,
  cn,
} from '@nifty/ui';
import {
  bridge,
  lua,
  money,
  wornItems,
  type Character,
  type InventoryItem,
  type InventoryPush,
  type InventoryView,
  type NearbyPlayer,
} from './contract';
import { usePanelSettings, type PanelSettings } from './usePanelSettings';
import { ItemTile } from './ItemTile';
import { ItemMenu, type MenuAction } from './ItemMenu';
import { QuantityPicker } from './QuantityPicker';
import { TargetPicker } from './TargetPicker';

/* ------------------------------------------------------------------ state shapes */

interface Hud {
  inventory: InventoryView;
  /** `undefined` until an `enterWorld` arrives; a refresh with no character keeps the old one. */
  character: Character | undefined;
}

const EMPTY_INVENTORY: InventoryView = {
  items: [],
  usedSlots: 0,
  totalSlots: 0,
  usedWeight: 0,
  maxWeight: 0,
};

const EMPTY_HUD: Hud = { inventory: EMPTY_INVENTORY, character: undefined };

/** What a confirmed quantity is for. */
type Intent = 'use' | 'give' | 'drop' | 'split';

const INTENT_LABEL: Record<Intent, string> = {
  use: 'Benutzen',
  give: 'Geben',
  drop: 'Wegwerfen',
  split: 'Aufteilen',
};

/**
 * One modal, one union, one slot.
 *
 * The vanilla panel kept three independent module-level variables
 * (`menuState` / `pickerState` / `targetPickerState`) plus a fourth piece of
 * module state for the settings popover, and every dismiss path had to remember
 * to clear the other three. Two of them could be on screen at once and the
 * "only one layer is up" rule existed only as an ESC handler that checked two of
 * the three selectors. Here it is unrepresentable to get wrong.
 */
type Modal =
  | { kind: 'context'; item: InventoryItem; x: number; y: number }
  | { kind: 'quantity'; item: InventoryItem; intent: Intent; min: number; initial: number }
  | { kind: 'target'; item: InventoryItem; quantity: number; targets: NearbyPlayer[] };

const SECTION_VISIBILITY: {
  value: string;
  label: string;
  key: keyof PanelSettings;
}[] = [
  { value: 'backpack', label: 'Rucksack zeigen', key: 'showBackpack' },
  { value: 'outfit', label: 'Outfit zeigen', key: 'showOutfit' },
  { value: 'quick', label: 'Quick Access zeigen', key: 'showQuickAccess' },
  { value: 'environment', label: 'Umgebung zeigen', key: 'showEnvironment' },
];

/* ------------------------------------------------------------------ helpers */

/**
 * The bootstrap payload is `{ items = {}, … }` in Lua, and a CEF JSON encoder is
 * free to turn an empty table into `{}` rather than `[]`. The old panel only
 * survived that because `.length` on an object is `undefined` — falsy, so the
 * "Rucksack ist leer." branch happened to win. Normalising once is honest
 * instead of lucky.
 */
function normaliseInventory(view: InventoryView | undefined): InventoryView | undefined {
  if (!view || typeof view !== 'object') return undefined;
  return {
    ...view,
    items: Array.isArray(view.items) ? view.items : [],
  };
}

function giverName(item: InventoryItem): string | undefined {
  const name = item.metadata?.giver_name;
  return typeof name === 'string' && name.length > 0 ? name : undefined;
}

/* ------------------------------------------------------------------ panel */

export function Inventory() {
  const [open, setOpen] = React.useState(false);
  const [hud, setHud] = React.useState<Hud>(EMPTY_HUD);
  const [modal, setModal] = React.useState<Modal | null>(null);
  const [settingsOpen, setSettingsOpen] = React.useState(false);
  const [settings, setSettings] = usePanelSettings();

  /* ---- Lua -> panel ------------------------------------------------- */

  const applyPush = React.useCallback((push?: InventoryPush) => {
    setHud((prev) => {
      const inventory = normaliseInventory(push?.inventory);
      return {
        // An absent inventory key keeps the cached one, exactly like the old
        // `data.inventory || hud.inventory`.
        inventory: inventory ?? prev.inventory,
        // …but an absent CHARACTER key means "keep the old one", not "clear it":
        // the character is simply not known yet on the first open.
        character: push && push.character !== undefined ? push.character : prev.character,
      };
    });
    setOpen(true);
  }, []);

  React.useEffect(() => bridge.on('inventory:open', applyPush), [applyPush]);
  React.useEffect(() => bridge.on('inventory:refresh', applyPush), [applyPush]);
  React.useEffect(
    () =>
      bridge.on('inventory:close', () => {
        setOpen(false);
        // The vanilla panel emptied the panel body but left its picker overlays
        // on `document.body`, so closing the inventory with the "Wie viele?"
        // dialog up left the dialog floating over the game. Unmounting drops it.
        setModal(null);
        setSettingsOpen(false);
      }),
    [],
  );

  /* ---- Escape unwinds one layer at a time ---------------------------- */

  React.useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      // The open modal has its own Escape handler and stops propagation.
      if (modal) return;
      if (settingsOpen) {
        setSettingsOpen(false);
        return;
      }
      void lua.closePanel();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, modal, settingsOpen]);

  /* ---- actions ------------------------------------------------------- */

  const armGive = React.useCallback(async (item: InventoryItem, quantity: number) => {
    const res = await lua.enterGiveMode({
      code: item.code,
      itemId: item.id,
      quantity,
    });
    if (!res.ok) return;
    if (res.value.ok !== true) return;
    setModal({
      kind: 'target',
      item,
      quantity,
      targets: Array.isArray(res.value.targets) ? res.value.targets : [],
    });
  }, []);

  const runAction = React.useCallback(
    (item: InventoryItem, intent: Intent, quantity: number) => {
      switch (intent) {
        case 'use':
          void lua.useItem({ code: item.code, quantity, itemId: item.id });
          return;
        case 'give':
          void armGive(item, quantity);
          return;
        case 'drop':
          void lua.discardItemOnGround({ code: item.code, quantity, itemId: item.id });
          return;
        case 'split':
          void lua.splitStack({ itemId: item.id, quantity });
          return;
      }
    },
    [armGive],
  );

  /**
   * A single-unit item fires straight away; a stack opens the picker first.
   * `Aufteilen` always opens the picker, defaulting to one LESS than the stack
   * so the split has something to move — the server keeps `quantity` behind and
   * creates a new row with the remainder.
   */
  const onMenuAction = React.useCallback(
    (item: InventoryItem, action: MenuAction) => {
      if (action === 'split') {
        setModal({
          kind: 'quantity',
          item,
          intent: 'split',
          min: 1,
          initial: Math.max(1, item.quantity - 1),
        });
        return;
      }

      const intent: Intent = action === 'use' ? 'use' : action === 'give' ? 'give' : 'drop';

      if (item.quantity > 1) {
        setModal({ kind: 'quantity', item, intent, min: 1, initial: item.quantity });
        return;
      }

      setModal(null);
      runAction(item, intent, 1);
    },
    [runAction],
  );

  /* ---- settings popover ---------------------------------------------- */

  React.useEffect(() => {
    if (!settingsOpen) return;
    const onDown = (e: MouseEvent) => {
      const target = e.target as Element | null;
      if (target && target.closest('[data-inv-settings]')) return;
      setSettingsOpen(false);
    };
    // capture, so it runs before the buttons below re-open it on a second click.
    document.addEventListener('mousedown', onDown, true);
    return () => document.removeEventListener('mousedown', onDown, true);
  }, [settingsOpen]);

  const activeSections = SECTION_VISIBILITY.filter((s) => settings[s.key]).map((s) => s.value);

  const onSectionVisibility = React.useCallback(
    (next: string[]) => {
      const patch: Partial<PanelSettings> = {};
      for (const section of SECTION_VISIBILITY) {
        patch[section.key] = next.indexOf(section.value) !== -1;
      }
      setSettings(patch);
    },
    [setSettings],
  );

  /* ---- render -------------------------------------------------------- */

  const worn = wornItems(hud.character?.appearance);
  const items = hud.inventory.items;

  if (!open) return null;

  return (
    <div className="fixed inset-0 flex flex-col bg-[var(--color-background)]/92 text-[var(--color-foreground)]">
      {/* ---- top bar ---- */}
      <header className="flex items-center justify-between border-b border-[color:var(--color-foreground)]/10 px-6 py-4">
        <h1 className="text-base font-semibold uppercase tracking-[0.18em] text-[var(--color-amber)]">
          INVENTORY
        </h1>
        <Button
          variant="outline"
          size="icon"
          aria-label="Schließen"
          onClick={() => void lua.closePanel()}
          className="h-7 w-7 text-base font-normal normal-case tracking-normal"
        >
          ×
        </Button>
      </header>

      <div className="flex-1 overflow-y-auto px-6 py-5">
        {/* ---- header row: title, capacity, settings cog ---- */}
        <div className="flex items-baseline gap-4 px-1 pb-1">
          <h2 className="text-[22px] font-bold tracking-[0.04em] text-[var(--color-amber)]">
            INVENTORY
          </h2>
          <span className="text-xs text-[var(--color-muted-foreground)]">
            {hud.inventory.usedSlots}/{hud.inventory.totalSlots} Plätze ·{' '}
            {money(hud.inventory.usedWeight)}/{money(hud.inventory.maxWeight)} KG
          </span>

          <div className="relative ml-auto" data-inv-settings>
            <button
              type="button"
              title="Inventar-Einstellungen"
              aria-label="Inventar-Einstellungen"
              aria-expanded={settingsOpen}
              onClick={(e) => {
                e.stopPropagation();
                setSettingsOpen((v) => !v);
              }}
              className={cn(
                'rounded border border-[color:var(--color-foreground)]/10 px-2 py-0.5',
                'text-sm text-[var(--color-muted-foreground)] transition-colors',
                'hover:border-[var(--color-amber)] hover:text-[var(--color-foreground)]',
                settingsOpen && 'border-[var(--color-amber)] text-[var(--color-amber)]',
              )}
            >
              ⚙
            </button>

            {settingsOpen ? (
              <Card className="absolute right-0 top-7 z-30 w-60 bg-[var(--color-card)]/95 p-3">
                <ToggleGroup
                  type="multiple"
                  value={activeSections}
                  onValueChange={onSectionVisibility}
                  className="flex-col items-stretch gap-1"
                >
                  {SECTION_VISIBILITY.map((section) => (
                    <ToggleGroupItem
                      key={section.value}
                      value={section.value}
                      className="justify-start"
                    >
                      {section.label}
                    </ToggleGroupItem>
                  ))}
                </ToggleGroup>
              </Card>
            ) : null}
          </div>
        </div>

        <Separator className="mb-3 opacity-60" />

        {/* ---- four sections ----
            All four are always rendered and hidden with the shared `.hidden`
            rule, so switching one off leaves the remaining three in their
            original grid columns instead of reflowing. That is the layout the
            vanilla stylesheet documented and the one players have seen. */}
        <div className="grid min-h-[22rem] grid-cols-4 gap-2.5">
          {/* BACKPACK */}
          <section
            className={cn(
              'flex min-h-0 flex-col gap-2 overflow-hidden rounded-[var(--radius-panel)]',
              'border border-[var(--color-border)] bg-black/30 p-2',
              !settings.showBackpack && 'hidden',
            )}
          >
            <div className="pb-1.5 text-center text-[11px] font-semibold tracking-[0.18em] text-[var(--color-muted-foreground)]">
              BACKPACK
            </div>

            {items.length === 0 ? (
              <EmptyState text="Rucksack ist leer." />
            ) : (
              <ScrollArea className="min-h-0 flex-1">
                <ul className="grid grid-cols-3 gap-1.5">
                  {items.map((item) => (
                    <ItemTile
                      key={item.id}
                      label={item.name || item.code}
                      quantity={item.quantity}
                      // `unitWeight` is the weight of ONE unit; the tile shows
                      // the row's weight so it agrees with the header's total.
                      weight={item.unitWeight * item.quantity}
                      giverName={giverName(item)}
                      onContextMenu={(e) => {
                        e.preventDefault();
                        setModal({ kind: 'context', item, x: e.clientX, y: e.clientY });
                      }}
                    />
                  ))}
                </ul>
              </ScrollArea>
            )}
          </section>

          {/* OUTFIT — read-only, derived from character.appearance */}
          <section
            className={cn(
              'flex min-h-0 flex-col gap-2 overflow-hidden rounded-[var(--radius-panel)]',
              'border border-[var(--color-border)] bg-black/30 p-2',
              !settings.showOutfit && 'hidden',
            )}
          >
            <div className="pb-1.5 text-center text-[11px] font-semibold tracking-[0.18em] text-[var(--color-muted-foreground)]">
              OUTFIT
            </div>

            {worn.length === 0 ? (
              <EmptyState text="Kein Outfit gespeichert." />
            ) : (
              <ScrollArea className="min-h-0 flex-1">
                <ul className="grid grid-cols-3 gap-1.5">
                  {worn.map((w) => (
                    <ItemTile key={w.label} label={w.label} quantity={1} weight={0} readOnly />
                  ))}
                </ul>
              </ScrollArea>
            )}
          </section>

          {/* QUICK ACCESS — five empty slots, reserved for hotbar bindings */}
          <section
            className={cn(
              'flex min-h-0 flex-col gap-2 overflow-hidden rounded-[var(--radius-panel)]',
              'border border-[var(--color-border)] bg-black/30 p-2',
              !settings.showQuickAccess && 'hidden',
            )}
          >
            <div className="pb-1.5 text-center text-[11px] font-semibold tracking-[0.18em] text-[var(--color-muted-foreground)]">
              QUICK ACCESS
            </div>
            <ScrollArea className="min-h-0 flex-1">
              <ul className="flex flex-col gap-1.5">
                {[1, 2, 3, 4, 5].map((index) => (
                  <li
                    key={index}
                    className="flex min-h-9 items-center gap-2 rounded border border-[var(--color-border)] bg-black/40 px-2.5"
                  >
                    <span className="text-sm font-semibold text-[var(--color-amber)]">
                      {index}
                    </span>
                  </li>
                ))}
              </ul>
            </ScrollArea>
          </section>

          {/* ENVIRONMENT — reserved for world-dropped stacks */}
          <section
            className={cn(
              'flex min-h-0 flex-col gap-2 overflow-hidden rounded-[var(--radius-panel)]',
              'border border-[var(--color-border)] bg-black/30 p-2',
              !settings.showEnvironment && 'hidden',
            )}
          >
            <div className="pb-1.5 text-center text-[11px] font-semibold tracking-[0.18em] text-[var(--color-muted-foreground)]">
              ENVIRONMENT
            </div>
            <EmptyState text="Noch nichts abgelegt." />
          </section>
        </div>
      </div>

      {/* ---- one modal, never two ---- */}
      {modal?.kind === 'context' ? (
        <ItemMenu
          item={modal.item}
          x={modal.x}
          y={modal.y}
          onAction={(action) => onMenuAction(modal.item, action)}
          onDismiss={() => setModal(null)}
        />
      ) : null}

      {modal?.kind === 'quantity' ? (
        <QuantityPicker
          item={modal.item}
          intentLabel={INTENT_LABEL[modal.intent]}
          initial={modal.initial}
          min={modal.min}
          onConfirm={(quantity) => {
            const item = modal.item;
            const intent = modal.intent;
            setModal(null);
            runAction(item, intent, quantity);
          }}
          onCancel={() => setModal(null)}
        />
      ) : null}

      {modal?.kind === 'target' ? (
        <TargetPicker
          item={modal.item}
          quantity={modal.quantity}
          targets={modal.targets}
          onDismiss={() => setModal(null)}
        />
      ) : null}
    </div>
  );
}

function EmptyState({ text }: { text: string }) {
  return (
    <p className="px-1.5 py-4 text-center text-[11px] italic text-[var(--color-muted-foreground)]">
      {text}
    </p>
  );
}