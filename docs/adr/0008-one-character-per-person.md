# One character per person

Each whitelisted account owns exactly one character. The character is the primary entity in the data model:
character UUID as the stable key, with the account as its owner (ADR-0001, ADR-0005). There is no character
cap to administer and no alt accounts, which keeps identity deep and moderation unambiguous.

## Consequences

- Departments become fragile. With 20–40 players and one character each, a police force of four or five
  people is two absences away from collapse, and a weekend-only server makes absences the normal case.
- Mitigation adopted: **jobs are open to anyone.** No application, no qualification, no minimum hours to
  join. A department can never be permanently empty because anyone may sign up; it is merely thin on a
  quiet weekend. This trades professional depth for reliability, which is the right trade at this scale.
- Alternative rejected: staff-gated or event-gated character creation. It produces stronger individual
  characters but multiplies the launch workload and delays every system that has to wait on "a character
  exists".
- Applications are per person, not per character (ADR-0007), so this decision does not affect the
  whitelist flow.