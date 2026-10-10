# Phone numbers are server-assigned and permanent

A character receives a number automatically when the character is created. The player does not choose it,
and it never changes.

**Not player-chosen** because a chosen number becomes a social object players fight over, and needs
collision handling, reservation and a rule for what happens when two people want the same digits. All of
that cost buys nothing on a 20–40 player whitelist.

**Permanent** because the number is the routing key for permanent message history (ADR-0004). A character
who changed their number would strand every message and email ever sent to them — the people who have
their number could no longer reach them, and the history becomes unreachable rather than merely old. A new
number is a new character.

## Consequences

- **No collision handling is needed.** The server assigns at creation inside a transaction, and the unique
  constraint on the number is a backstop rather than a daily concern.
- Area coding by district can be added later at no structural cost: it changes only how the random number
  is generated, not the schema or any of the routing that depends on it. It is a formatting decision, not
  a design decision.
- The number is public — it appears in contacts and in the character's own profile. It is therefore part
  of what social content exposes, and its permanence is part of what makes a permanent feed workable.
- Because numbers never change, a reported or abused number is a reliable handle for moderation across the
  whole life of a character.