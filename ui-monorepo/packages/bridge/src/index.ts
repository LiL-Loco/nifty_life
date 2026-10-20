/**
 * The Lua <-> NUI contract, typed.
 *
 * WHY THIS EXISTS
 *
 * Every NUI frame on the client is a separate CEF browser, and all of them
 * share one `SendNUIMessage` channel. A bare `action = 'open'` therefore
 * reaches every resource: nifty-inventory, nifty-creator and nifty-world all
 * shipped an `open` action, and nifty-world's copy of that name unhid a stale,
 * never-wired creator form that covered the real one and swallowed its clicks.
 * That bug cost an evening and no amount of runtime measurement could have
 * explained it — `IsNuiFocused` reads the game's own bookkeeping and happily
 * reports success while the clicks land on the wrong frame.
 *
 * The fix is not runtime vigilance, it is the type system. `createBridge` takes
 * an action map for THIS resource, so `on('open', …)` does not compile — only
 * the prefixed names that resource's Lua side actually sends do. A collision
 * becomes a build failure instead of a silent no-op.
 */

/** The CEF global FiveM injects. Declared here so panels need no local shim. */
declare global {
  interface Window {
    GetParentResourceName?: () => string;
  }
  // eslint-disable-next-line no-var
  var GetParentResourceName: () => string;
}

export interface NuiMessage<T = unknown> {
  action: string;
  data?: T;
}

export interface NuiCallOptions {
  /** Abort after this many milliseconds. Defaults to 10s. */
  timeoutMs?: number;
}

/** A callback registered on the Lua side with `RegisterNUICallback`. */
export type CallbackName = string;

/** Shape of the map a panel passes to `createBridge`. */
export type ActionMap = Record<string, (body: any) => void>;

export type Result<T> =
  | { ok: true; value: T }
  | { ok: false; error: string };

function resourceName(): string {
  const fn = window.GetParentResourceName;
  if (typeof fn !== 'function') {
    throw new Error(
      'GetParentResourceName is unavailable. This module must run inside a FiveM NUI frame.',
    );
  }
  return fn();
}

/**
 * Call a `RegisterNUICallback` handler on the Lua side of THIS resource.
 *
 * `https://`, never `http://` — the page itself is served from
 * `https://cfx-nui-<resource>/`, so an `http://` request is mixed content and
 * CEF blocks it before it leaves the browser. That single character blocked
 * every NUI callback in this project once already and the surface that
 * revealed it was a warning on an unrelated panel.
 */
export async function callLua<T = unknown>(
  name: CallbackName,
  body: unknown = {},
  options: NuiCallOptions = {},
): Promise<Result<T>> {
  const { timeoutMs = 10_000 } = options;
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(`https://${resourceName()}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body ?? {}),
      signal: controller.signal,
    });

    if (!res.ok) {
      return { ok: false, error: `NUI callback "${name}" answered ${res.status}` };
    }
    return { ok: true, value: (await res.json()) as T };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { ok: false, error: `NUI callback "${name}" failed: ${message}` };
  } finally {
    window.clearTimeout(timer);
  }
}

export interface Bridge<T extends ActionMap> {
  /** Fire a callback on the Lua side. Never throws — inspect `.ok`. */
  call<R = unknown>(name: CallbackName, body?: unknown): Promise<Result<R>>;
  /** Subscribe to one action. Returns an unsubscribe function. */
  on<K extends keyof T & string>(action: K, handler: (body: any) => void): () => void;
  /** Every action name this panel accepts, for exhaustiveness checks. */
  readonly actions: readonly (keyof T & string)[];
}

/**
 * Build a panel's bridge.
 *
 * `actions` is the panel's OWN list. It is the single place a prefix is
 * declared, so renaming an action is a compile error in exactly the files that
 * use it rather than a runtime trace in a log nobody reads.
 */
export function createBridge<T extends ActionMap>(actions: {
  received: readonly (keyof T & string)[];
}): Bridge<T> {
  return {
    actions: actions.received,

    call(name, body) {
      return callLua(name, body);
    },

    on(action, handler) {
      const listener = (event: MessageEvent) => {
        const msg = event.data as NuiMessage | undefined;
        if (!msg || msg.action !== action) return;
        handler(msg.data);
      };
      window.addEventListener('message', listener);
      return () => window.removeEventListener('message', listener);
    },
  };
}