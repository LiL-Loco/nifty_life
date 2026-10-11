-- ============================================================================
-- 029_clothing_accessory_items.sql
-- Nifty Life 2.0 — per-piece accessory item definitions
--
-- WHY
--
-- The wardrobe's "Anziehen" for masks, glasses, watches, rings, hats, etc.
-- is supposed to also create an inventory item the player carries. The
-- item exists for the lifetime of the wear — auto-created on equip, NOT
-- removed by the wardrobe's "Ablegen" (the item stays in the bag), and
-- only disappears via an explicit drop / give.
--
-- Each of these has max_stack=1 and stackable=0 so two copies of "the same
-- hat in the same colour" never coexist. Different fabrics live as
-- different items via metadata (collection, drawable, texture). A
-- Clothing-wardrobe key in the item_defs.metadata_schema flags what
-- metadata is carried.
--
-- slot -> code mapping (driven by the free-mode slot list):
--   component 1      -> clothing_mask
--   prop     0       -> clothing_hat
--   prop     1       -> clothing_glasses
--   prop     2       -> clothing_earring
--   prop     6       -> clothing_ring       (Schmuck / bracelet)
--   prop     7       -> clothing_watch
--
-- Halsketten (necklace) is not a free-mode slot - the game lacks a stand-
-- alone necklace anchor on the male/female ped model. Skipped on purpose
-- rather than mapped to a wrong slot.
-- ============================================================================

INSERT INTO item_defs
  (code, name, category, weight, stackable, max_stack, is_weapon, metadata_schema)
VALUES
  ('clothing_mask',     'Maske',         'clothing', 0.050, 0, 1, 0,
   JSON_OBJECT(
     'type', 'object',
     'required', JSON_ARRAY('kind','slot_id','collection','drawable','texture'),
     'properties', JSON_OBJECT(
       'kind', JSON_OBJECT('type', 'string', 'enum', JSON_ARRAY('component','prop')),
       'slot_id', JSON_OBJECT('type', 'integer'),
       'collection', JSON_OBJECT('type', 'string'),
       'drawable', JSON_OBJECT('type', 'integer'),
       'texture', JSON_OBJECT('type', 'integer')
     ))),
  ('clothing_hat',      'Kopfbedeckung', 'clothing', 0.100, 0, 1, 0,
   JSON_OBJECT('type','object','required', JSON_ARRAY('kind','slot_id','collection','drawable','texture'))),
  ('clothing_glasses',  'Brille',        'clothing', 0.050, 0, 1, 0,
   JSON_OBJECT('type','object','required', JSON_ARRAY('kind','slot_id','collection','drawable','texture'))),
  ('clothing_earring',  'Ohrring',       'clothing', 0.020, 0, 1, 0,
   JSON_OBJECT('type','object','required', JSON_ARRAY('kind','slot_id','collection','drawable','texture'))),
  ('clothing_ring',     'Ring',          'clothing', 0.020, 0, 1, 0,
   JSON_OBJECT('type','object','required', JSON_ARRAY('kind','slot_id','collection','drawable','texture'))),
  ('clothing_watch',    'Uhr',           'clothing', 0.100, 0, 1, 0,
   JSON_OBJECT('type','object','required', JSON_ARRAY('kind','slot_id','collection','drawable','texture')))
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  category = VALUES(category),
  weight = VALUES(weight),
  stackable = VALUES(stackable),
  max_stack = VALUES(max_stack),
  metadata_schema = VALUES(metadata_schema);
