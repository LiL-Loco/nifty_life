# Weekend window: Friday 19:00 to Sunday 22:00, 48 slots, one restart

The server runs roughly 27 hours a week, Friday 19:00 to Sunday 22:00, with 48 slots and a single restart on
Friday evening. Connections are **refused outside the window** rather than merely left unmaintained.

48 slots is chosen because OneSync is free up to 48 and nothing about this server needs more; a paid Cfx tier
starts above that and there is no reason to cross the line.

Connections are actively refused because a committed schedule is the point of a weekend server, and
unmaintained access quietly produces a Tuesday-evening crowd that never builds a character. The cost is
accepted knowingly: players will arrive when we are asleep, and that has to be answered in the onboarding
text rather than by staying online.

A single Friday restart bounds how much state can drift and doubles as the maintenance window, rather than
a daily restart that halves across the weekend and doubles admin attention.

## Consequences

- The window length feeds the economy: a longer open window means more Stütze payouts and more accumulated
  world state. Sizing the Stütze (ADR-0009) has to be done against this window, not in isolation.
- Refusing connections means the "world is frozen while you are off" rule (ADR-0004) needs no special
  handling — the server simply is not running Monday to Thursday.
- Artifact currency is an ongoing obligation from launch: server artifacts older than three months are
  unjoinable from the server browser regardless of target runtime, so updates must be applied during the
  weekday downtime.