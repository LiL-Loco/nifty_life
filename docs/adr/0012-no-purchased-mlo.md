# No purchased MLO — standard GTA interiors only

The server buys no map modifications. Buildings are the interiors GTA V ships with, or vanilla spaces
repurposed for a role. This is a deliberate budget and scope decision: he owns no assets, buys none, and
asset work is not part of the launch.

Vanilla GTA's enterable spaces are more than adequate once the story-mode interiors are counted. Relevant
ones include **Mission Row Police Station (captain's office and armory)**, Pillbox Hill Medical Center, the
Los Santos County Coroner Office, Union Depository and Blaine County Savings Bank, Humane Labs, Clucking
Bell Farms, Grand Banks Steel Foundry, Raven Slaughterhouse, Lester's Factory, the Max Renda construction
site, Vangelico, LifeInvader offices, and four residential safehouses (Franklin's aunt's house, Franklin's
mansion, Michael's house, Trevor's trailer).

**Correction:** an earlier draft of this ADR claimed GTA V has no enterable police station, on the grounds
that no LSPD building has an interior. That was wrong — Mission Row, the main LPD building, does have one,
with an armory. GTA V does lack a purpose-built *fire* station, and the branch stations at Vinewood, Vespucci,
La Mesa, Davis, Sandy Shores and Paleto Bay are exteriors only, but a police headquarters in vanilla assets
exists.

## Scope boundary: what "no MLO" permits

No purchased assets, and no hand-built map modifications. Stock GTA spaces only — including GTA Online
apartment interiors, which ship in the **base install** under `x64/dlcpacks/` (`dlcapartments`) and are
therefore not a purchase and not a custom asset. They are used heavily for housing (ADR-0013). Loading them
is an IPL request, not an MLO.

Excluded because they require custom assets or server-breaking natives: Cayo Perico (needs
`0x9A9D1BA639675CF1`, which hides the base map), Kosatka, submarine, bunker, nightclub and biker clubhouse
interiors, and anything surfaced only by ASI/ScriptHookV mods that enable unused or teleport-only spaces.

## Consequences

- Launch-gate items 6 and 11 (police, EMS, dispatch) have real workplaces in vanilla assets. LSPD is Mission
  Row; EMS is Pillbox. No stand-in, no repurpose, no warp door into an obviously wrong building.
- Housing has four vanilla safehouses plus repurposed commercial interiors, which is a genuine ceiling on how
  many distinct, visibly different homes can exist for a base that accumulates property over months
  (ADR-0004). This is now the main cost of the no-MLO decision, rather than the missing police station.
- Branch police stations exist as exteriors only. A single LSPD headquarters is fine at this scale; multiple
  divisions in separate buildings would need MLO.
- No purpose-built fire station exists in vanilla GTA. If fire is wanted as a department, it either shares a
  building with police or is dropped from scope.
- Business interiors exist in enough variety to support distinct businesses without MLO.
- Hand-built MLO remains available later and is logged as a v2 route to expanding housing variety. It is free
  but needs a genuine Blender and Codewalker skill ramp, and is not proposed for launch scope.
- "Vanilla" in this project means *the geography is GTA's*, not *every building is GTA's* — see the term
  definition recorded in the domain glossary.