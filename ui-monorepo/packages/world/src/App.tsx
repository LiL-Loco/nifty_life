import * as React from 'react';
import {
  INITIAL_STATE,
  onRender,
  onResult,
  send,
  type WorldState,
} from './contract';
import { Hud } from './components/Hud';
import { PanelShell } from './components/PanelShell';
import { Toast } from './components/Toast';

/** How long a result toast stays on screen. */
const TOAST_MS = 3500;

interface ToastState {
  ok: boolean;
  text: string;
}

/**
 * The HUD and panel shell — nifty-world's entire visible surface.
 *
 * Presentation only, same rule the old ui/app.js was written under: this file
 * draws what the server sent and forwards clicks. It never decides whether a
 * purchase is affordable or a job can be joined; every button sends a code and
 * the server answers with what actually happened.
 */
export function App() {
  const [state, setState] = React.useState<WorldState>(INITIAL_STATE);
  const [toast, setToast] = React.useState<ToastState | null>(null);
  const toastTimer = React.useRef<number | null>(null);

  React.useEffect(
    () =>
      onRender((data) => {
        // Replace wholesale rather than merge, so a field the server stopped
        // sending disappears instead of lingering from the last update. The
        // two that survive a miss are `money` and `inventory`: cl_world.lua
        // holds them in a State table that is always populated, and losing the
        // HUD's balance for one render would be worse than a stale frame.
        //
        // `inventory` and `character` are carried here because cl_world.lua
        // sends both and the old JS dropped them on the floor — which is why
        // the Sell button in the shop never once rendered.
        setState((prev) => ({
          money: data.money || prev.money,
          inventory: data.inventory || prev.inventory,
          character: data.character || null,
          jobs: data.jobs || [],
          jobCatalogue: data.jobCatalogue || [],
          shop: data.shop || [],
          properties: data.properties || [],
          vehicles: data.vehicles || [],
          panel: data.panel || null,
        }));
      }),
    [],
  );

  React.useEffect(
    () =>
      onResult(({ ok, message }) => {
        setToast({
          ok,
          text: message || (ok ? 'Erledigt.' : 'Das hat nicht geklappt.'),
        });

        // Re-arming rather than stacking: a burst of results shows the newest,
        // and the timer is a ref so replacing it does not re-subscribe anything.
        if (toastTimer.current !== null) window.clearTimeout(toastTimer.current);
        toastTimer.current = window.setTimeout(() => {
          toastTimer.current = null;
          setToast(null);
        }, TOAST_MS);
      }),
    [],
  );

  React.useEffect(
    () => () => {
      if (toastTimer.current !== null) window.clearTimeout(toastTimer.current);
    },
    [],
  );

  /* ---- Escape closes the panel ----------------------------------------- */

  /**
   * This resource was the only one without one. Shop and jobs opened on F2/F3
   * and closed on F5, so a player who opened the shop by muscle memory had no
   * way out that a person would reach for first — and since this panel also
   * takes the keyboard now, "no cursor, no Escape" would have been a trap.
   *
   * The rule every other panel here uses: an Escape typed INTO a text field
   * belongs to that field. Closing the whole shop because someone cleared a
   * search box is its own bug, and two panels in this repo already document it.
   */
  const panelOpen = state.panel !== null;
  React.useEffect(() => {
    if (!panelOpen) return undefined;

    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;

      const tag = (event.target as HTMLElement | null)?.tagName || '';
      if (['INPUT', 'TEXTAREA', 'SELECT'].includes(tag)) return;

      event.preventDefault();
      void send('closePanel', {});
    };

    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [panelOpen]);

  return (
    <>
      <Hud money={state.money} jobs={state.jobs} />
      {toast ? <Toast ok={toast.ok} text={toast.text} /> : null}
      <PanelShell state={state} />
    </>
  );
}