# The phone is a device; the account belongs to the character

Phones are inventory items. The number, Messages, Email and social account behind a phone belong to the
**character**, permanently, and are not tied to any particular handset.

## The model

- **Device** — a generic phone in inventory. It has no identity of its own.
- **Account** — the character's number, social handle and message history. Bound to the character, never
  transferred.
- **Access rule** — a character may use the phone menu while carrying *any* phone device. Not only their
  original one.

This means handing a phone to another player moves hardware, not identity. The giver loses the ability to
open the menu because they no longer hold a device. The receiver gains a device that does nothing, because
they are not the account holder.

The original alternative — a phone locked to one character — was rejected: it makes replacement
impossible, so losing a phone would permanently cost a character their entire social and messaging life.

## Consequences

- **Phones become a money sink.** An inactive handset must be activated before use, so a replacement is
  something a character has to acquire and pay for. This matters more than it first appears: the
  no-grind economy (ADR-0009) currently gives a broke player no reason to want money, because nothing in
  the design costs anything. A priced, breakable device is one of the few sinks that scales with how badly
  a player is doing.
- **Messages and email keep arriving while the owner has no device.** They are simply unreadable until the
  character holds a phone. That pressure is deliberate — it is what makes replacing a lost phone matter
  rather than being an afterthought.
- The phone depends on the inventory system (ADR-0014 layer 4) for existence, and on layer 5 for transfer.
  It cannot be finished before inventory exists.
- **A stolen phone is recoverable rather than catastrophic.** Because the account is unbound, the character
  buys a new handset and is back. This avoids the permanent-impersonation hole that locking a phone to a
  character would create: a thief gains hardware, never the ability to post, message or read email as the
  victim.