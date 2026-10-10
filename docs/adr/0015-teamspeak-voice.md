# Teamspeak-based voice instead of in-game voice

Proximity voice is provided by an external Teamspeak server rather than `pma-voice` or any in-game voice
resource. Players connect to Teamspeak alongside the game.

## Why this was chosen

In-game proximity voice is the weakest part of a FiveM RP server — range-based, routed through the game
client, and frequently the first thing a cheater attacks. Teamspeak moves voice off the game server entirely.
It also gives genuinely better channel structure (departments can have persistent channels that survive a
restart, independent of who is logged in), and it hands the solo administrator real voice moderation tools
— mute, kick, move — that in-game voice does not provide well. For a server where one person is the entire
staff team, having enforcement authority over voice is worth a great deal.

## Consequences

- **A character now has two linked identities**: the Discord ID, which is the whitelist key (ADR-0007), and a
  Teamspeak UID, which gates voice. A player must link both. This is extra onboarding friction and an extra
  failure mode where a player is whitelisted but cannot talk, or vice versa.
- **The Teamspeak server must not be open.** An unauthenticated Teamspeak server lets non-whitelisted people
  listen in on police and EMS channels, which defeats the whitelist entirely. TS access has to be driven from
  the same whitelist data as the game server. Treat this as part of the whitelist enforcement (launch-gate
  items 17–18), not as separate setup.
- **Players must install and configure Teamspeak.** This is the single biggest source of join friction on the
  server, and it will cost applicants who expected to just press play. It has to be explained before the
  application, in the onboarding text, not discovered on first connection.
- **Licensing is free and this is no longer an open question.** Teamspeak 3 Server itself costs nothing: one
  virtual server and 32 slots unlicensed, and the Non-Commercial Licence covers up to 512 slots free of charge.
  We run 48 slots (ADR-0010), so the paid commercial licence is not needed and never will be at this size.
  Positioning within the world is provided by SaltyChat, which is GPL-3.0 open source
  (`v10networkscom/saltychat-fivem`) and free for servers below 100 slots; it gives GTA-synchronised 3D
  positional audio on top of Teamspeak rather than the range-based fallback Teamspeak offers on its own.
  Both facts are recorded here so the "check the licence tier" line does not come back as an open task.
- **The voice stack therefore has two layers, and only one is ours to own.** Teamspeak carries the audio and
  the moderation surface; SaltyChat carries the position. Neither is the game's own voice stack, so neither
  is reachable from a game cheat, which is the property this ADR was written to buy.
- Voice outages are now separate from game outages. A game restart (ADR-0010) does not automatically take
  Teamspeak down, which is an advantage: voice can persist across the Friday restart if wanted.
- If Enhanced is ever adopted (ADR-0001), this decision is unaffected — it does not rely on Mumble, which is
  one of the reasons it is the safer long-term choice.