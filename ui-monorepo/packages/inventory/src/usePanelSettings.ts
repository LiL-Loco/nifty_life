import * as React from 'react';

export interface PanelSettings {
  showBackpack: boolean;
  showOutfit: boolean;
  showQuickAccess: boolean;
  showEnvironment: boolean;
}

/**
 * The storage key is unchanged from the vanilla panel, so an existing player's
 * toggles survive the migration.
 *
 * Note what this is NOT: the old comment above the loader said "per-character"
 * and the implementation has always been per-CEF-origin. Every panel shares one
 * CEF profile per client, so these are per-player-per-machine, and they survive a
 * character switch. Changing that needs a Lua round-trip, not a JS tweak.
 */
const STORAGE_KEY = 'nifty.inv.settings.v1';

const DEFAULTS: PanelSettings = {
  showBackpack: true,
  showOutfit: true,
  showQuickAccess: true,
  showEnvironment: true,
};

function load(): PanelSettings {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as Partial<PanelSettings> | null;
      if (parsed && typeof parsed === 'object') {
        // Merge over the defaults: a key added in a later version must not come
        // back as `undefined`, which would read as "section hidden".
        return {
          showBackpack: parsed.showBackpack ?? DEFAULTS.showBackpack,
          showOutfit: parsed.showOutfit ?? DEFAULTS.showOutfit,
          showQuickAccess: parsed.showQuickAccess ?? DEFAULTS.showQuickAccess,
          showEnvironment: parsed.showEnvironment ?? DEFAULTS.showEnvironment,
        };
      }
    }
  } catch (_) {
    /* private mode, quota, corrupt JSON — the defaults are the right answer */
  }
  return DEFAULTS;
}

function save(settings: PanelSettings): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
  } catch (_) {
    /* ignore */
  }
}

/**
 * Reads once on mount, writes on every change. The ref exists so `set` keeps a
 * stable identity: writing from inside a `setState` updater would run the write
 * twice under StrictMode and is a side effect in the render phase besides.
 */
export function usePanelSettings(): [
  PanelSettings,
  (patch: Partial<PanelSettings>) => void,
] {
  const [settings, setSettings] = React.useState<PanelSettings>(load);
  const ref = React.useRef(settings);

  const update = React.useCallback((patch: Partial<PanelSettings>) => {
    const next = { ...ref.current, ...patch };
    ref.current = next;
    save(next);
    setSettings(next);
  }, []);

  return [settings, update];
}