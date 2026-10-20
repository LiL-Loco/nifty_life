import * as React from 'react';
import { clothingBridge, send, type ClothingOpen } from './contract';
import { PanelFrame } from './chrome';
import { Store } from './Store';
import { Wardrobe } from './Wardrobe';

/**
 * nifty-clothing — one NUI page, two screens.
 *
 * THE HAND-WRITTEN DISCRIMINATION IS GONE
 *
 * The vanilla page ran two IIFEs on one `window.message` stream. Each filtered
 * the other out by hand, four lines in total, comparing against action strings
 * that no message actually used — and then BOTH still switched on a bare
 * `'open'`, which Lua never sends, so the filter was load-bearing for nothing.
 *
 * `data.mode` is the discriminator, so it is a TypeScript union here: the
 * wardrobe and the store are two renderings of one value, they cannot both be
 * mounted, and a mode that is neither simply does not open the panel.
 *
 * Visibility is owned by Lua. `clothing:open` opens, `clothing:close` closes,
 * and nothing in here flips it — the close button and the Escape key both go
 * through `closePanel`, and wait for the broadcast to come back.
 */
export function ClothingPanel() {
  const [view, setView] = React.useState<ClothingOpen | null>(null);

  const close = React.useCallback(() => {
    void send('closePanel', {});
  }, []);

  React.useEffect(
    () =>
      clothingBridge.on('clothing:open', (data: ClothingOpen) => {
        if (!data || (data.mode !== 'wardrobe' && data.mode !== 'store')) return;
        setView(data);
      }),
    [],
  );

  React.useEffect(
    () => clothingBridge.on('clothing:close', () => setView(null)),
    [],
  );

  return (
    <PanelFrame open={view !== null} onClose={close}>
      {view ? <Screen view={view} /> : null}
    </PanelFrame>
  );
}

/**
 * Mounted only when the panel is open, and only for the one mode that is open.
 *
 * Unmounting is the whole teardown story: each screen's `clothingBridge.on`
 * subscriptions, its Escape listener and every outstanding timer go with it,
 * where the old page left handlers registered for the life of the CEF frame
 * and could only ever be removed by id.
 */
function Screen({ view }: { view: ClothingOpen }) {
  return view.mode === 'wardrobe' ? <Wardrobe open={view} /> : <Store open={view} />;
}