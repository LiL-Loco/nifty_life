# Economy structure: unconditional Stütze, optional farming

The economy is defined structurally now and priced later. What is settled:

- **A Stütze is paid every 15 minutes to every connected character, unconditionally.** No employment
  requirement, no liveness check, no anti-idle check, no per-session cap. Anyone connected receives it.
- **Farming systems exist but are never mandatory.** Every aspirational purchase — vehicle, property,
  tuning, weapons — must be reachable without touching a farm loop. That is the governing principle.
- **Prices are placeholders until the economy is worked out in a later pass.**

## The unresolved risk this defers

Unconditional payment removes every obstacle to AFK collecting, so the Stütze's *amount* is the only thing
preventing it from becoming the dominant strategy. If the amount ever reaches subsistence, idling outranks
working and the jobs layer becomes decorative.

The mitigation is not eligibility — it is **sizing**: set the payout below what a character needs to live on.
It then functions as a symbolic floor that guarantees nobody is stuck at zero, and never becomes an
alternative playstyle because it is never sufficient. This is a pricing decision and is deliberately
deferred, so it is the single item most likely to be got wrong when numbers are eventually chosen.

This decision also runs against ADR-0004 (permanent world): money only accumulates over months, so sinks
that scale with wealth — rent, fuel, insurance, upkeep, business costs — carry the balancing work that
grinding does on a conventional server. Wealth must be a burden as well as an asset.

## Consequences

- Wealth must be a burden as well as an asset. There is no grind to drain the economy, so recurring costs
  that scale with what a character owns do the work instead. This also respects "nothing is lost" — a
  large house is expensive, not deleted.
- Nothing about pricing should be treated as decided. Any placeholder committed to the database must be
  trivially bulk-editable, because the first tuning pass will change most of them.