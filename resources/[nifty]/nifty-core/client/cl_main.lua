--- Client side. Intentionally near-empty at layer 2.
---
--- ADR-0011: Lua owns game state and rules; the web stack owns presentation
--- only. Nothing here is allowed to decide anything — the client is untrusted,
--- so this file is an input surface, not a source of truth.

local started = false

CreateThread(function()
  while not NetworkIsSessionStarted() do
    Wait(200)
  end

  started = true
  print('[nifty-core] client ready')
end)

--- Convenience for future layers. `Nifty.Settings` is populated server-side;
--- the client copy arrives via a replicated event when layer 3 lands.
RegisterNetEvent('nifty:client:bootstrap', function(payload)
  Nifty = Nifty or {}
  Nifty.Settings = payload and payload.settings or {}
end)

exports('isReady', function()
  return started
end)