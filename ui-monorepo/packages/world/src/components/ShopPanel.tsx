import * as React from 'react';
import { Button } from '@nifty/ui';
import { send, type InventoryView, type ShopEntry } from '../contract';
import { formatMoney } from '../format';

/**
 * Shop.
 *
 * Two rules from the old panel, kept because they are about honesty rather
 * than looks:
 *
 * 1. Sell only shows for things the character actually carries. The server
 *    would refuse the rest anyway; hiding the button keeps the panel honest
 *    about what is possible.
 * 2. The row sends a code. Whether the purchase is affordable is the server's
 *    answer, not this panel's guess.
 */
export function ShopPanel({
  shop,
  inventory,
  cash,
}: {
  shop: ShopEntry[];
  inventory: InventoryView;
  cash: number;
}) {
  // One pass over the carried items instead of a `.find` per catalogue row —
  // the catalogue is every item in the game and the backpack is short.
  const carried = React.useMemo(() => {
    const map = new Map<string, number>();
    for (const item of inventory.items) map.set(item.code, item.quantity);
    return map;
  }, [inventory.items]);

  return (
    <div className="flex flex-col gap-3">
      <p className="m-0 text-xs text-[rgba(242,242,240,0.55)]">
        Bargeld: {formatMoney(cash)}
      </p>

      <ul className="m-0 list-none p-0">
        {shop.map((entry) => {
          const quantity = carried.get(entry.code);
          return (
            <li
              key={entry.code}
              className="flex items-center gap-3 border-b border-[rgba(255,255,255,0.05)] py-2.5 last:border-b-0"
            >
              <span className="flex-1 text-sm text-[var(--color-foreground)]">
                {entry.name}
              </span>
              <span className="text-xs tabular-nums text-[rgba(242,242,240,0.55)]">
                {formatMoney(entry.price)}
              </span>

              <Button
                size="sm"
                variant="ghost"
                onClick={() => {
                  void send('buy', { code: entry.code, quantity: 1 });
                }}
              >
                Kaufen
              </Button>

              {quantity !== undefined ? (
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => {
                    void send('sell', {
                      code: entry.code,
                      // Floored and floored-at-one because Shop:sell rejects
                      // anything below 1 outright; an item row can never hold
                      // less, and a rejected click looks like a dead button.
                      quantity: Math.max(1, Math.floor(quantity)),
                    });
                  }}
                >
                  Verkaufen ({quantity})
                </Button>
              ) : null}
            </li>
          );
        })}
      </ul>

      <div className="flex gap-2">
        <Button
          size="sm"
          onClick={() => {
            void send('deposit', { amount: 100 });
          }}
        >
          100 $ einzahlen
        </Button>
        <Button
          size="sm"
          variant="ghost"
          onClick={() => {
            void send('withdraw', { amount: 100 });
          }}
        >
          100 $ abheben
        </Button>
      </div>
    </div>
  );
}