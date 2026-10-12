--[[
  Clothing store trigger.

  2026-10-12: The NUI driver (cl_nui.lua) now opens the store through
  a vanilla-JS NUI. The legacy NativeUI surface that lived here
  (buildItemMenu, openSlotPicker) is gone. This file keeps only the
  open-trigger the proximity target fires; the NUI handles the
  per-slot lists, the buy buttons, and the toast.
]]

local RESOURCE = GetCurrentResourceName()

-- nifty:client:openStore is fired by the proximity target (see
-- cl_targets.lua) when the player presses K inside a store radius.
-- cl_nui.lua listens for the same event and pushes the NUI open.
RegisterNetEvent('nifty:client:openStore', function(storeId)
  -- No-op here; the handler in cl_nui.lua does the work. The event
  -- exists so a TriggerEvent('nifty:client:openStore', id) from any
  -- script opens the store UI without each script needing to know
  -- about the NUI driver.
end)
