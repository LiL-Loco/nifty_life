# GTA5 RP Server

A whitelisted, weekend-only FiveM roleplay server built from scratch with no framework, running vanilla GTA
geography over a hand-rolled character, economy and persistence layer.

## Identity

**Account**:
The human being behind the game. Owns exactly one character and carries **two** linked identities — a
Discord ID, which is the whitelist key, and a Teamspeak UID, which gates voice. An application, a ban and a
voice channel membership all attach to the account.
_Avoid_: Player, user, customer

**Character**:
The in-world persona a single account plays. The primary entity in the data model and the thing that owns
property, money and inventory. Never reused between accounts.
_Avoid_: Player, avatar, skin

**Whitelist**:
The set of accounts permitted to connect, keyed by Discord ID and checked at `playerConnecting`.
_Avoid_: Approval, access list

**Application**:
A submitted request to join, moving through *submitted → under review → approved / rejected*. Reviewed by a
human, never auto-approved. Distinct from a Whitelist entry — the website may create Applications but may
never create a Whitelist entry.
_Avoid_: Signup, registration, request

## World

**The Window**:
The Friday 19:00 – Sunday 22:00 period in which the server runs. Connections are refused outside it. The
world is frozen while the server is off.
_Avoid_: Session, opening hours, cycle

**Downtime**:
Monday to Thursday. Not a pause between sessions — time genuinely does not advance, so nothing decays and
no Stütze accrues.
_Avoid_: Offline mode, maintenance

**Vanilla**:
The geography is GTA V's. Does **not** mean every building is GTA's — interiors are repurposed vanilla
spaces reached by warp doors. It also does not mean "no scripts": it means no framework clutter.
_Avoid_: Unmodded, stock, default

**Interior**:
Any building players can enter, taken from GTA V's stock spaces. Mission Row is the LSPD; Pillbox is EMS.
GTA ships no enterable fire station, and only the four safehouses plus commercial spaces work as housing.
_Avoid_: Building, room, MLO

**Department**:
A job with emergency powers — police, EMS, fire. Open to any character without qualification, so it can
never be permanently empty.
_Avoid_: Job, faction, organisation

## Communication

**Phone**:
A handset in inventory — generic hardware with no identity. It is what you need *a* of in order to
open your account; it is not tied to you. Handing one over moves hardware, not identity.
_Avoid_: Device, handset, phone account

**Account (phone)**:
The character's number, Message history, Email and social presence. Bound to the character permanently
and never transferred, so **any** phone a character carries will open it.
_Avoid_: SIM, phone, number

**Number**:
The character's phone number, assigned at character creation and stable forever. It routes Messages and
Email. Unlike a FiveM slot ID it is owned by a character and never recycled, so it is safe to address
mail to it (ADR-0001 does not apply).
_Avoid_: Phone number, MSISDN

**Message**:
A short direct text between two Numbers. The casual, immediate channel.
_Avoid_: SMS, DM, text

**Email**:
A longer addressed item delivered to a mailbox, separable from a Message. Used
for documents, official notices, and anything that should feel like paperwork.
_Avoid_: Mail, letter

**Post**:
A public entry on the network, visible to followers. **Only staff may remove one.**
A character cannot delete their own post — in roleplay you do not get to rewrite
your own history.
_Avoid_: Tweet, status, feed post

**Feed**:
The timeline of Posts from characters a player follows. Following is asymmetric.
_Avoid_: Timeline, wall

**Place**:
A named location attached to a Post at the time it is posted. It is an attribute,
not a tracker — there is no live occupancy list and no location history.
_Avoid_: Check-in, Places, venue

## Economy

**Stütze**:
An unconditional payment to every connected character on a fixed interval. It is a floor that guarantees
nobody is stuck at zero, never a living wage — its amount is deliberately set *below* subsistence so that
idling is never worth doing.
_Avoid_: Welfare, salary, stipend

**Farming**:
A repeatable money loop. It exists, and it is never required — every aspirational purchase must be reachable
without it. Contrast with a Stütze, which is a floor, not a strategy.
_Avoid_: Grinding, grind loop

**Sink**:
A recurring cost that scales with what a character owns — rent, fuel, insurance, upkeep. With no mandatory
grinding, sinks carry the balancing work a grind loop would otherwise do.
_Avoid_: Tax, cost, expense