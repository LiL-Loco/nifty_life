# Target FiveM Legacy, not FiveM for GTAV Enhanced

We build the server on FiveM Legacy rather than FiveM for GTAV Enhanced. Enhanced is labelled early access with no published end-of-beta date, cannot run escrow-protected resources at all, removes Mumble (and with it pma-voice) and P2P sync, and requires .NET 10 in place of Mono. Nothing in the project's concept needs any of that, so we take the stable target and revisit only when escrow ships and early access ends.

To keep this from becoming a dead end, the persistence layer must never key player-owned rows by FiveM slot ID: Enhanced recycles those IDs on disconnect, so every such row would silently reassign to the wrong player. A stable surrogate key (character UUID) is required from the first schema migration regardless of which runtime we launch on.

## Consequences

- The runtime choice stays reversible as long as the data layer is ID-safe — the expensive half of migration is the data, not the target.
- pma-voice remains available, so voice needs no redesign for the foreseeable future.
- Enhanced's breaking changes (key-value DB file migration, `stream_enhanced`, single endpoint, .NET 10) are not our problem yet, but the promised migration script has not shipped — re-check before any future move.
- Server artifacts older than three months are unjoinable from the server browser regardless of target, so the release cadence is an ongoing constraint either way.