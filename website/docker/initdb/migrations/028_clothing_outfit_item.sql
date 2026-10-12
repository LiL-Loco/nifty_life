-- ============================================================================
-- 028_clothing_outfit_item.sql
-- Nifty Life 2.0 — clothing_outfit item definition
--
-- WHY
--
-- Outfits (migration 026's `character_outfits` table) are named loadouts.
-- The user wants players to *pack* an outfit into the inventory, hold it
-- like any other stackable item, and *use* it from there to apply. That
-- requires an item definition the inventory accepts.
--
-- `clothing_outfit` is one code per outfit-as-an-item. Its metadata is the
-- outfit_id (a CHAR(36) referencing character_outfits.id on a specific
-- character). The item exists separately from the outfit row: deleting
-- the row breaks the item, but holding the item does not delete the row.
-- This matches phone/id_card whose data lives on the character's row, not
-- in the inventory.
--
-- Stackable, max 10 - lets the player keep a small set of favourite
-- outfits on hand without filling a slot each. Weight 0.05: an outfit
-- is invisible in your pocket.
--
-- `metadata_schema` documents the shape so future inventory UIs can
-- render outfit items correctly without hardcoding knowledge here.
-- ============================================================================

INSERT INTO item_defs
  (code, name, category, weight, stackable, max_stack, is_weapon, metadata_schema)
VALUES
  ('clothing_outfit', 'Outfit', 'clothing', 0.050, 1, 10, 0,
   JSON_OBJECT(
     'type', 'object',
     'required', JSON_ARRAY('outfit_id'),
     'properties', JSON_OBJECT(
       'outfit_id', JSON_OBJECT('type', 'string', 'description', 'character_outfits.id')
     )
   ))
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  category = VALUES(category),
  weight = VALUES(weight),
  stackable = VALUES(stackable),
  max_stack = VALUES(max_stack),
  metadata_schema = VALUES(metadata_schema);
