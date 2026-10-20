/**
 * Wire adapter for the arm-wrestling panel.
 *
 * WHY A LOCAL ADAPTER INSTEAD OF `createBridge` FROM @nifty/bridge
 *
 * `createBridge` dispatches on `msg.action` (`{ action: 'show' }`). The
 * arm-wrestling resource is the ONLY one in this project whose Lua side sends
 * `{ type = 'show' or 'hide' }` and `{ type = 'tick', pos = pos }`. Verified by
 * grepping every `SendNUIMessage(...)` call under F:/GTA5/resources/[nifty].
 *
 * The wider recommendation in the contract notes is to normalize the Lua side
 * to `{ action = ..., data = { ... } }` so all six panels share one dispatcher.
 * That would touch client/cl_armwrestling.lua, which is outside this package's
 * edit boundary (and outside any single-package migration's authority). Until
 * the Lua side is normalized, this adapter is the typed seam that lets the
 * panel compile-check action names against a local ActionMap and dispatch on
 * the actual wire field.
 *
 * ONCE THE LUA SIDE SWITCHES TO `action`/`data`, THIS FILE COLLAPSES TO A
 * ONE-LINER `createBridge`-CALL. The exported `wire` API is intentionally
 * shaped like `Bridge<T>` from @nifty/bridge so the swap is mechanical.
 */

import { callLua } from '@nifty/bridge';

/**
 * Per-verb payload shapes. `Record<string, never>` keeps the body parameter
 * non-optional even though the Lua side never sends fields for `show`/`hide`,
 * so the handler signature is uniform.
 */
export type ArmwrestlingActionMap = {
  show: Record<string, never>;
  hide: Record<string, never>;
  tick: { pos: number };
};

type ArmwrestlingAction = keyof ArmwrestlingActionMap;
type ArmwrestlingHandler<K extends ArmwrestlingAction> = (
  body: ArmwrestlingActionMap[K],
) => void;

export interface WireBridge {
  /** Subscribe to one wire action. Returns an unsubscribe function. */
  on<K extends ArmwrestlingAction>(action: K, handler: ArmwrestlingHandler<K>): () => void;
  /** Every action name this panel accepts, for exhaustiveness checks. */
  readonly actions: readonly ArmwrestlingAction[];
  /**
   * Call a `RegisterNUICallback` handler on the Lua side. The arm-wrestling
   * resource currently registers zero of them (the NUI is a pure listener),
   * but the handle is exposed so future round-trips type-check.
   */
  call<R = unknown>(name: string, body?: unknown): ReturnType<typeof callLua<R>>;
}

const ACTIONS = ['show', 'hide', 'tick'] as const;

/**
 * Build the local bridge.
 *
 * `actions.received` is the panel's OWN action list, exactly like
 * `createBridge`. The names are the only strings that will dispatch — a typo
 * is a compile error.
 */
export function createWireBridge(actions: { received: readonly ArmwrestlingAction[] }): WireBridge {
  const allowed = new Set<string>(actions.received);

  return {
    actions: actions.received,

    call(name, body) {
      return callLua(name, body);
    },

    on(action, handler) {
      // The generic K gives compile-checked names; the runtime payload shape
      // is fixed by the same verb, but TypeScript won't track the connection
      // through a generic dispatcher. `dispatch` is the single place that has
      // to cast — everywhere else stays typed.
      const dispatch = handler as unknown as (body: unknown) => void;

      const listener = (event: MessageEvent) => {
        // Wire shape is `{ type: 'show' | 'hide' | 'tick', [pos?: number] }`.
        // We dispatch on `type`; the bridge module would dispatch on `action`.
        const raw = event.data as { type?: unknown; pos?: unknown } | undefined;
        if (!raw || typeof raw.type !== 'string') return;
        if (raw.type !== action) return;
        if (!allowed.has(raw.type)) return;

        // Normalise the payload per verb:
        //   show / hide -> {}                  (no fields on the wire)
        //   tick         -> { pos: number }   (Lua fields `pos` at root)
        // The bridge module is left untouched: it doesn't know about
        // top-level verb fields or the `type` discriminator, so we shape the
        // argument by hand here. Clamping matches the original JS: `pos`
        // falls back to 0.5 if missing/NaN, then clamped to [0, 1].
        if (action === 'tick') {
          const n = Number(raw.pos);
          const p = Number.isFinite(n) ? n : 0.5;
          dispatch({ pos: Math.max(0, Math.min(1, p)) });
        } else {
          dispatch({});
        }
      };

      window.addEventListener('message', listener);
      return () => window.removeEventListener('message', listener);
    },
  };
}

export const wire = createWireBridge({ received: ACTIONS });
