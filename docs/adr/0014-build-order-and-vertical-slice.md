# Build order: spine first, content last

Work proceeds in dependency order, and each layer is finished before the next begins:

1. **Schema** — tables, character UUIDs, ID-safe keying (ADR-0001, ADR-0005)
2. **Persistence layer** — oxmysql access, migrations, the save/load path every other system uses
3. **Identity** — whitelist check at connect, character create/select (ADR-0007, ADR-0008)
4. **Money and inventory** — the primitives every job and purchase depends on
5. **Generic systems** — the job framework and the ownership primitive, built once so that housing,
   vehicles and businesses become data rather than subsystems
6. **Content** — actual jobs, actual properties, actual businesses

Content is last deliberately. Building it early is the trap: the fun work is layer 6, and starting there
means discovering at layer 6 that the abstraction chosen at layer 5 was wrong — after twenty systems already
depend on it.

## Vertical slice

Before any content work begins, one complete thin path is proven end to end **on the developer's own
machine, with no players**: connect, create a character, take a job, earn money, buy something, own it,
reconnect, and find it still there.

This is an internal milestone, not a release. ADR-0003 forbids a public launch before completion; it does not
forbid verifying the spine privately. Without it, "everything before launch" means architectural faults
surface only after every system is built — with no players present, there is no external signal that anything
is wrong. The slice exists to turn that into a week-two problem instead of a final-month one.

## Consequences

- The slice is the project's first real test of the ID-safe keying and the persistent-entity handling in
  ADR-0004, because "reconnect and it is still there" is exactly what those two decisions govern.
- Layer 5 abstractions are the ones most worth getting right in one pass, because everything in layer 6 is
  data written against them.
- Delays are expected to appear at layers 1 and 5. That is normal and is cheaper than discovering the same
  delay at layer 6.