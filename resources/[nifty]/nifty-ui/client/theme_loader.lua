-- Theme loader.
--
-- Loads themes/nifty.json via zUI.GetTheme, applies it to the active UI, and
-- sends a `theme:load` NUI event so the vanilla-JS page can write the
-- colour/font values into `:root` CSS variables.
--
-- The page is the source of truth for the visible appearance; the JSON
-- supplies the values. The two stay in sync because the page reads the
-- same keys zUI-v2 uses internally (colors.primary, colors.background,
-- font, etc.), and the shim's callers don't see either.

local RESOURCE = GetCurrentResourceName()

-- zUI-v2 sets the `zUI` table as a top-level global from common.lua.
-- We get the same object via its declared export, then call methods on it.
local zUI = exports[RESOURCE]:getObject()

Citizen.CreateThread(function()
  -- Wait for the network to be up before applying a theme, otherwise
  -- the NUI might miss the early message. zUI-v2 does the same dance
  -- for its own init (see vendor/zui/common.lua).
  repeat Wait(100) until NetworkIsPlayerActive(PlayerId())

  local theme = zUI.GetTheme('nifty')
  zUI.ApplyTheme(theme)

  -- Mirror to the NUI so the page can write CSS variables.
  TriggerNuiEvent('theme:load', theme)

  print(('[%s] menu theme ready'):format(RESOURCE))
end)
