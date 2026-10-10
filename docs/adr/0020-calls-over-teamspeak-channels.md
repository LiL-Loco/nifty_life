# Voice calls use Teamspeak channels

In-game phone calls are implemented by moving both parties into a temporary
Teamspeak channel, which is closed when the call ends. No FiveM voice is used for calls.

## Why

Teamspeak is already required for the server (ADR-0015), so calls reuse
infrastructure players have installed rather than introducing a second voice system
with worse quality. Mixing FiveM proximity voice with Teamspeak would also be confusing.

## The prerequisite this depends on

**A call cannot be placed until the player's Teamspeak UID is known.** The
Teamspeak server cannot tell which TS account belongs to which FiveM player on its
own. So call support requires the Teamspeak-UID linking that ADR-0015 already
planned, stored in `accounts.teamspeak_uid`.

In practice the client reads its own UID from Teamspeak and submits it; the server
verifies that UID against the Teamspeak server query before trusting it. The linking
step is therefore not optional groundwork — it is the first thing calls depend on, and
it shares its shape with the Discord-ID linking from ADR-0007.

## Consequences

- **Requires Teamspeak server-query access.** Automating channel create, move and
  delete needs a serveradmin-level query account. That is an operational dependency
  on a system outside this codebase, and the piece most likely to be harder than
  expected. Verify the channel lifecycle end to end early, before building the phone
  UI on top of it.
- **Channel lifecycle is a resource concern.** Every call creates and destroys a
  channel, so abuse is possible — a player spamming calls could flood the Teamspeak
  server with channels. Calls need server-side rate limiting and a cap on concurrent
  calls before launch.
- **Calls degrade gracefully.** If Teamspeak is down, calls fail but the rest of the
  phone — Messages, Email, social — is unaffected, because those are database-backed
  and know nothing about Teamspeak.
- Proximity voice, in normal play, remains proximity voice. Teamspeak is still the
  server's voice; this decision adds a phone feature that happens to use it.