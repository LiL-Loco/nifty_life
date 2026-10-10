# Bob74_IPL as the IPL loader

Interior loading is handled by the community resource **Bob74_IPL** (`github.com/Bob74/Bob74_IPL`), rather than
by hand-writing `RequestIpl` calls across our own resources. IPLs must be requested per client; Bob74_IPL
centralises that and exposes an `ipl` config table so specific interiors are enabled or disabled in one place.

The aggregator `fivem-ipl` (originally esx-community, now heavily forked) bundles `bob74_ipl` plus several
other IPL lists into one "load everything" resource. **We use Bob74_IPL, not the aggregator.**

## Why this does not contradict ADR-0002

ADR-0002 rejects frameworks — resources that decide your architecture and own your player model. An IPL loader
decides nothing about how characters, money or jobs work. It is infrastructure, the same category as the voice
and chat resources we already agreed to borrow. Loading an interior is a platform mechanic with no sane
alternative implementation; writing it ourselves would be busywork, not authorship.

## Load strategy: selective, not global

**We do not load every IPL on the server.** Bob74_IPL supports selecting exactly which interiors to request,
and we enable only the ones the housing catalogue and job interiors actually use.

The aggregator's approach — requesting the full IPL universe on every client — makes every interior on the map
resident for every player. At our scale (48 slots, one city) that is wasted memory and streaming for interiors
nobody will ever visit, and it also has the side effect of enabling map-wide clutter that has nothing to do with
Nifty Life 2.0's design.

Selective loading also means the config file *is* the housing design: if Eclipse Towers is not in the list, it
does not exist.

## Consequences

- This is the **only third-party runtime dependency** on a hand-rolled server, and it is a supply-chain
  consideration: if Bob74 stops maintaining the resource or the repository disappears, housing and job interiors
  break until we replace it. Fork it in-repo at first use rather than depending on a remote release.
- Bob74_IPL also resolves the outstanding verification items in the housing catalogue — whether every
  `apa_v_mp_h_*` style loads, and whether the suburban house shells carry interiors — because toggling an IPL
  on and off and watching the result is exactly what the resource is for. That should be the first thing built
  after the persistence layer, since the housing catalogue is otherwise an unverified plan.
- IPL names fail silently when wrong. A property that does not appear in game is a typo, not a bug report —
  so interior availability must be verified per entry, not assumed.