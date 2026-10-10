# Full character creator with a NUI appearance editor

Characters are authored in a complete editor, not chosen from a fixed list. The editor is a NUI page
(ADR-0011): Lua owns the rules and persistence, the web stack owns the interface only.

## Appearance is stored collection-based, not by global index

FiveM exposes two indexing schemes for ped drawables and props:

- **Global index** — an index into the combined set of all collections. Stable within a game build,
  **shifted by every Title Update**.
- **Collection name + local index** — an index within one named collection. **Stable across Title
  Updates**.

We store `collection` + `drawable` (local) + `texture` per slot, never a global index. The base game
collection is the empty string `""`; DLC collections are named (e.g. `female_heist`,
`mp_f_bikerdlc_01`). Component ids run 0..12 and prop anchor points run 0..12.

This is the decision the whole feature rests on. Storing global indexes is the conventional approach and
it is a trap: the first Title Update after launch would silently restyle every existing character, with
no error and no way to detect it from the stored data.

## Natives used

Discovery and counts (all client-side):
`GetPedCollectionsCount`, `GetPedCollectionName`,
`GetNumberOfPedCollectionDrawableVariations`, `GetNumberOfPedCollectionTextureVariations`,
`GetNumberOfPedCollectionPropDrawableVariations`, `GetNumberOfPedCollectionPropTextureVariations`

Application:
`SetPedCollectionComponentVariation`, `SetPedCollectionPropIndex`,
`SetPedCollectionPreloadVariationData`, `SetPedCollectionPreloadPropData`

Validation and read-back:
`IsPedCollectionComponentVariationValid`, `GetPedDrawableVariationCollectionName`,
`GetPedDrawableVariationCollectionLocalIndex`

The preload natives are not optional polish. Swapping an unloaded drawable streams it in and hitches the
frame; without preloading, the creator feels broken while the player drags across clothing options.

## Consequences

- **The editor necessarily runs client-side, which makes appearance an untrusted input.** The collection
  natives are documented as client-only, so the server cannot ask the engine whether a given combination
  is valid. The server must therefore validate against an allowlist: permitted collection names per
  component, and drawable/texture ranges per collection held in configuration. Storing the client's JSON
  verbatim would let a player persist an arbitrary, un-renderable appearance.
- The appearance editor is the largest single UI build in the project and belongs to layer 3 (identity),
  not to content. It is the thing that makes a character feel like the player's own, so it is not the
  place to economise.
- Component and prop discovery is cheap on first run and cacheable. Enumerating every collection and
  variation for 13 components should happen once at resource start, not per UI open.
- Previews must load the ped model itself from the ped-models reference; freemode models carry the full
  component range, other models far less.