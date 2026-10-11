-- NIFTY PATCH: focus is owned by nifty-core's broker (cl_focus.lua).
-- The shim in nifty-ui/client/shim.lua monkey-patches zUI.ManageFocus
-- at load time to call Focus:acquire / Focus:release on the broker.
-- Do not call SetNuiFocus from this file.
zUI.ManageFocus = function(_)
  -- no-op
end
