--[[
  Per-character clothing ownership (ADR-0001 layer 3, mirrored on Identity).

  Owns the `character_clothing` table. The table stores the per-piece list of
  everything a character owns; `characters.appearance` keeps its existing role
  of storing the currently-equipped loadout, and this module is the gate
  between them - `checkEquipped` is what `Identity.saveCharacter` runs to
  stop a client from equipping something it does not own.

  The module is a global so the facade can hand it out by reference, the same
  pattern `Db` / `Identity` / `Validate` use. Functions here run on the
  server only.
]]

local RESOURCE = GetCurrentResourceName()

Owned = {}

-- ----------------------------------------------------------------------------
-- DB primitives
-- ----------------------------------------------------------------------------

local function grantOne(characterId, kind, slotId, collection, drawable, texture, source)
  if type(characterId) ~= 'string' or characterId == '' then return end
  if kind ~= 'component' and kind ~= 'prop' then return end
  if type(slotId) ~= 'number' or slotId < 0 or slotId > 255 then return end
  if type(collection) ~= 'string' or collection == '' then return end
  if type(drawable) ~= 'number' or drawable < 0 then return end
  if type(texture) ~= 'number' or texture < 0 then return end

  -- Re-validating against the same rules Validate.appearance uses would be
  -- belt-and-suspenders. Skipping today because Owned.grant is reached from
  -- two places only: the creator finish path (server-validated already) and
  -- the purchase path (server-validated already). If a third caller appears,
  -- route it through Validate.appearance first.
  Db.update([[
    INSERT IGNORE INTO character_clothing
      (character_id, kind, slot_id, collection, drawable, texture, source)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  ]], {
    characterId, kind, slotId, collection,
    tostring(drawable), tostring(texture), source,
  }, 'owned:grant')
end

function Owned.grant(characterId, kind, slotId, collection, drawable, texture, source)
  grantOne(characterId, kind, slotId, collection, drawable, texture, source or 'seed')
end

function Owned.has(characterId, kind, slotId, collection, drawable, texture)
  if type(characterId) ~= 'string' or characterId == '' then return false end
  if type(slotId) ~= 'number' or type(drawable) ~= 'number' or type(texture) ~= 'number' then
    return false
  end

  local row = Db.one([[
    SELECT 1 AS hit
      FROM character_clothing
     WHERE character_id = ?
       AND kind = ?
       AND slot_id = ?
       AND collection = ?
       AND drawable = ?
       AND texture = ?
     LIMIT 1
  ]], {
    characterId, kind, tostring(slotId), collection,
    tostring(drawable), tostring(texture),
  }, 'owned:has')

  return row ~= nil
end

--- All owned pieces for a character. Returns an empty table, never nil.
---
--- `kind` and `slotId` are optional filters. No filter = whole inventory.
--- Order is stable: kind, slot_id, collection, drawable, texture.
function Owned.list(characterId, kind, slotId)
  if type(characterId) ~= 'string' or characterId == '' then return {} end

  local sql, params
  if kind and slotId then
    sql = [[
      SELECT kind, slot_id, collection, drawable, texture, source, acquired_at
        FROM character_clothing
       WHERE character_id = ? AND kind = ? AND slot_id = ?
       ORDER BY collection, drawable, texture
    ]]
    params = { characterId, kind, tostring(slotId) }
  elseif kind then
    sql = [[
      SELECT kind, slot_id, collection, drawable, texture, source, acquired_at
        FROM character_clothing
       WHERE character_id = ? AND kind = ?
       ORDER BY slot_id, collection, drawable, texture
    ]]
    params = { characterId, kind }
  elseif slotId then
    sql = [[
      SELECT kind, slot_id, collection, drawable, texture, source, acquired_at
        FROM character_clothing
       WHERE character_id = ? AND slot_id = ?
       ORDER BY kind, collection, drawable, texture
    ]]
    params = { characterId, tostring(slotId) }
  else
    sql = [[
      SELECT kind, slot_id, collection, drawable, texture, source, acquired_at
        FROM character_clothing
       WHERE character_id = ?
       ORDER BY kind, slot_id, collection, drawable, texture
    ]]
    params = { characterId }
  end

  local rows = Db.all(sql, params, 'owned:list') or {}
  -- oxmysql's insertId / affectedRows helpers are not relevant here; coerce
  -- numeric-looking strings to numbers so callers can compare with `==`.
  for _, r in ipairs(rows) do
    r.slot_id  = tonumber(r.slot_id)
    r.drawable = tonumber(r.drawable)
    r.texture  = tonumber(r.texture)
  end
  return rows
end

--- Has every piece in `appearance` already been granted to this character?
---
--- Returns (true, nil) when everything the loadout wears is owned. Returns
--- (false, '<reason>') on the first un-owned piece. The reason names the
--- shape (`component 11 / foo / 7 / 2`) so a log line is enough to diagnose
--- without re-running the query.
function Owned.checkEquipped(characterId, appearance)
  if type(appearance) ~= 'table' then return true, nil end

  if type(appearance.components) == 'table' then
    for slotId, slot in pairs(appearance.components) do
      if type(slot) == 'table' then
        local sid = tonumber(slotId)
        if sid and not Owned.has(characterId, 'component', sid,
                                  slot.collection, slot.drawable, slot.texture) then
          return false, ('component %d / %s / %s / %s'):format(
            sid,
            tostring(slot.collection),
            tostring(slot.drawable),
            tostring(slot.texture))
        end
      end
    end
  end

  if type(appearance.props) == 'table' then
    for slotId, slot in pairs(appearance.props) do
      if type(slot) == 'table' then
        local sid = tonumber(slotId)
        if sid and not Owned.has(characterId, 'prop', sid,
                                  slot.collection, slot.drawable, slot.texture) then
          return false, ('prop %d / %s / %s / %s'):format(
            sid,
            tostring(slot.collection),
            tostring(slot.drawable),
            tostring(slot.texture))
        end
      end
    end
  end

  return true, nil
end

-- ----------------------------------------------------------------------------
-- Backfill
--
-- One-shot seed of the owned table from characters with a saved appearance.
-- Skip when any seed row already exists: that means a previous boot ran the
-- migration, so subsequent boots have nothing to do. Cheap when skipped; the
-- first run is the only one that does real work.
-- ----------------------------------------------------------------------------

local function backfillOnce()
  local existingSeed = Db.one([[
    SELECT 1 AS hit FROM character_clothing WHERE source = 'seed' LIMIT 1
  ]], {}, 'owned:backfill:probe')
  if existingSeed ~= nil then return end

  -- A backfill of N rows = 2N INSERTs. The query is cheap; the per-row work
  -- is not. Iterate one character at a time so a slow row does not block the
  -- rest of the boot.
  local rows = Db.all([[
    SELECT id, appearance
      FROM characters
     WHERE appearance IS NOT NULL
       AND appearance <> ''
  ]], {}, 'owned:backfill:scan') or {}

  local granted = 0
  for _, row in ipairs(rows) do
    local ok, appearance = pcall(json.decode, row.appearance)
    if ok and type(appearance) == 'table' then
      for slotId, slot in pairs(appearance.components or {}) do
        if type(slot) == 'table' then
          local sid = tonumber(slotId)
          if sid and slot.collection and slot.drawable and slot.texture then
            Owned.grant(row.id, 'component', sid,
                        slot.collection, slot.drawable, slot.texture, 'seed')
            granted = granted + 1
          end
        end
      end
      for slotId, slot in pairs(appearance.props or {}) do
        if type(slot) == 'table' then
          local sid = tonumber(slotId)
          if sid and slot.collection and slot.drawable and slot.texture then
            Owned.grant(row.id, 'prop', sid,
                        slot.collection, slot.drawable, slot.texture, 'seed')
            granted = granted + 1
          end
        end
      end
    end
  end

  if granted > 0 then
    print(('[%s] owned backfill: granted %d owned pieces across %d characters'):format(
      RESOURCE, granted, #rows))
  end
end

-- Run after the DB is up. Defer until then so the migration is actually
-- applied - a server boot that races the migration must not start owned-mode
-- against a missing table.
Db.ready(function()
  local ok, err = pcall(backfillOnce)
  if not ok then
    print(('[%s] owned backfill failed: %s'):format(RESOURCE, tostring(err)))
  end
end)

-- ----------------------------------------------------------------------------
-- Outfits
--
-- A named list of owned pieces. Pieces are NOT copied: the outfit row in
-- `character_outfits` is the named root, `character_outfit_pieces` carries
-- the body, and an apply re-checks Owned.has before writing. A piece the
-- character can no longer equip (e.g. shared across characters in a future
-- feature) would refuse to apply rather than silently missing.
-- ----------------------------------------------------------------------------

local function outfitRefreshPieceCounts(characterId)
  -- Optional helper: read piece-counts per outfit in one round-trip. Returns
  -- a map keyed by outfit id. Used by `Outfit.list` below so the wardrobe
  -- menu can label each outfit ("Dienst - 4 Teile") without re-querying.
  local rows = Db.all([[
    SELECT outfit_id, COUNT(*) AS pieces
      FROM character_outfit_pieces
     WHERE outfit_id IN (SELECT id FROM character_outfits WHERE character_id = ?)
     GROUP BY outfit_id
  ]], { characterId }, 'owned:outfit:counts') or {}

  local byOutfit = {}
  for _, r in ipairs(rows) do
    byOutfit[r.outfit_id] = tonumber(r.pieces) or 0
  end
  return byOutfit
end

--- All outfits for a character. Names + piece counts, never the bodies.
function Owned.listOutfits(characterId)
  if type(characterId) ~= 'string' or characterId == '' then return {} end

  local rows = Db.all([[
    SELECT id, name, created_at, applied_at
      FROM character_outfits
     WHERE character_id = ?
     ORDER BY name
  ]], { characterId }, 'owned:outfit:list') or {}

  local counts = outfitRefreshPieceCounts(characterId)
  for _, o in ipairs(rows) do
    o.pieces = counts[o.id] or 0
  end

  return rows
end

--- The pieces of one outfit, in the shape `applyAppearanceParts` likes.
---
--- Returns `{ components = { [slot_id] = {collection, drawable, texture}, ... },
---             props      = { ... }, missing = { [slot_id] = true, ... } }`.
---
--- `missing` lists the slots whose piece is no longer owned. The caller can
--- choose to apply the rest (with the missing slot unchanged) or refuse.
--- V1 refuses - a partial outfit is what "wardrobe glitched" looks like.
function Owned.getOutfit(characterId, outfitId)
  if type(characterId) ~= 'string' or characterId == '' then return nil end
  if type(outfitId) ~= 'string' or outfitId == '' then return nil end

  local root = Db.one([[
    SELECT id, name FROM character_outfits
     WHERE id = ? AND character_id = ?
     LIMIT 1
  ]], { outfitId, characterId }, 'owned:outfit:root')
  if root == nil then return nil end

  local pieces = Db.all([[
    SELECT kind, slot_id, collection, drawable, texture
      FROM character_outfit_pieces
     WHERE outfit_id = ?
     ORDER BY kind, slot_id
  ]], { outfitId }, 'owned:outfit:pieces') or {}

  local result = {
    id         = outfitId,
    name       = root.name,
    components = {},
    props      = {},
    missing    = {},
  }

  for _, p in ipairs(pieces) do
    local sid = tonumber(p.slot_id)
    if sid then
      local entry = {
        collection = p.collection,
        drawable   = tonumber(p.drawable),
        texture    = tonumber(p.texture),
      }
      if p.kind == 'component' then
        result.components[tostring(sid)] = entry
      elseif p.kind == 'prop' then
        result.props[tostring(sid)] = entry
      end
    end
  end

  return result
end

--- Save the character's currently-equipped loadout as a named outfit.
---
--- `appearance` is the validated shape `Validate.appearance` already cleans
--- to. Re-walking it here would duplicate the contract; this function trusts
--- its input, the same way Identity.saveCharacter does.
---
--- On a duplicate name for the same character, the existing outfit's pieces
--- are deleted (FK cascade) and the new row replaces it under the same
--- unique key. The intent matches the user's "speichern als Dienst" verb -
--- they overwrite when they pick a taken name.
---
--- Pieces are inserted in a transaction so a partial outfit (root row but no
--- body) cannot be observed by another query. The root row itself is outside
--- the transaction because we need its `insertId`; losing it to a crash
--- leaves no orphan (the FK goes the other way). Returns (true, outfitId)
--- or (false, reason).
function Owned.saveOutfit(characterId, name, appearance)
  if type(characterId) ~= 'string' or characterId == '' then
    return false, 'no character'
  end
  if type(name) ~= 'string' then return false, 'no name' end
  name = name:match('^%s*(.-)%s*$') or ''
  if #name == 0 then return false, 'empty name' end
  if #name > 64 then name = name:sub(1, 64) end

  if type(appearance) ~= 'table' then return false, 'no appearance' end

  -- Every piece in the outfit must be owned. The character wore this loadout
  -- just now (per the caller), which means Owned.checkEquipped already
  -- passed; but a defence-in-depth pass costs nothing.
  local ok, err = Owned.checkEquipped(characterId, appearance)
  if not ok then return false, ('not owned: ' .. tostring(err)) end

  -- Drop a duplicate-name outfit, if any. Pieces cascade away via FK; the
  -- new INSERT below then satisfies the (character_id, name) UNIQUE key.
  local dup = Db.one([[
    SELECT id FROM character_outfits
     WHERE character_id = ? AND name = ?
     LIMIT 1
  ]], { characterId, name }, 'owned:outfit:save:probe')
  if dup and dup.id then
    Db.update('DELETE FROM character_outfits WHERE id = ?',
              { dup.id }, 'owned:outfit:save:drop')
  end

  local outfitId = Nifty.newUuid()
  Db.insert([[
    INSERT INTO character_outfits (id, character_id, name)
    VALUES (?, ?, ?)
  ]], { outfitId, characterId, name }, 'owned:outfit:save:root')

  -- Pieces, in one transaction. Each slot contributes at most one row
  -- because the outfit_pieces PK is (outfit_id, kind, slot_id).
  local statements = {}
  for slotId, slot in pairs(appearance.components or {}) do
    if type(slot) == 'table' then
      local sid = tonumber(slotId)
      if sid and slot.collection and slot.drawable and slot.texture then
        statements[#statements + 1] = {
          sql = [[INSERT INTO character_outfit_pieces
                    (outfit_id, kind, slot_id, collection, drawable, texture)
                  VALUES (?, 'component', ?, ?, ?, ?)]],
          params = {
            outfitId, tostring(sid),
            tostring(slot.drawable), tostring(slot.texture), slot.collection,
          },
        }
      end
    end
  end
  for slotId, slot in pairs(appearance.props or {}) do
    if type(slot) == 'table' then
      local sid = tonumber(slotId)
      if sid and slot.collection and slot.drawable and slot.texture then
        statements[#statements + 1] = {
          sql = [[INSERT INTO character_outfit_pieces
                    (outfit_id, kind, slot_id, collection, drawable, texture)
                  VALUES (?, 'prop', ?, ?, ?, ?)]],
          params = {
            outfitId, tostring(sid),
            tostring(slot.drawable), tostring(slot.texture), slot.collection,
          },
        }
      end
    end
  end
  if #statements > 0 then
    Db.transaction(statements, 'owned:outfit:save:pieces')
  end

  return true, outfitId
end

--- Mark an outfit as "applied now". Cosmetic in V1; the column exists so
--- the wardrobe menu can sort by recency without a separate log table.
function Owned.touchOutfit(outfitId)
  if type(outfitId) ~= 'string' or outfitId == '' then return end
  Db.update([[
    UPDATE character_outfits SET applied_at = NOW() WHERE id = ?
  ]], { outfitId }, 'owned:outfit:touch')
end

--- Delete an outfit by id. Refuses if the outfit belongs to a different
--- character - one character cannot delete another's outfit, even if they
--- guess the id.
function Owned.deleteOutfit(characterId, outfitId)
  if type(characterId) ~= 'string' or characterId == '' then return false end
  if type(outfitId) ~= 'string' or outfitId == '' then return false end

  Db.update([[
    DELETE FROM character_outfits
     WHERE id = ? AND character_id = ?
  ]], { outfitId, characterId }, 'owned:outfit:delete')

  return true
end

--- Rename. Empty names are refused; same-name rename is a no-op success.
function Owned.renameOutfit(characterId, outfitId, newName)
  if type(characterId) ~= 'string' or characterId == '' then return false, 'no character' end
  if type(outfitId) ~= 'string' or outfitId == '' then return false, 'no outfit' end
  if type(newName) ~= 'string' then return false, 'no name' end
  newName = newName:match('^%s*(.-)%s*$') or ''
  if #newName == 0 then return false, 'empty name' end
  if #newName > 64 then newName = newName:sub(1, 64) end

  -- Collision check; the UNIQUE key would catch it and turn the UPDATE
  -- into a duplicate-key error, which is harder to read than a clear "name
  -- taken" return.
  local clash = Db.one([[
    SELECT 1 AS hit FROM character_outfits
     WHERE character_id = ? AND name = ? AND id <> ?
     LIMIT 1
  ]], { characterId, newName, outfitId }, 'owned:outfit:rename:probe')
  if clash ~= nil then return false, 'name taken' end

  Db.update([[
    UPDATE character_outfits SET name = ?
     WHERE id = ? AND character_id = ?
  ]], { newName, outfitId, characterId }, 'owned:outfit:rename')

  return true
end

-- ----------------------------------------------------------------------------
-- Per-drawable, per-fabric variation pricing
--
-- The DB-backed pricebook. A row in `clothing_prices` overrides any Lua
-- default for that exact (kind, slot_id, collection, drawable, texture). The
-- Lua defaults live in nifty-clothing/shared/prices.lua (the curated
-- fallback); this module's job is just to look the row up and let the
-- caller chain a fallback.
--
-- The lookup is a synchronous read against `clothing_prices` (PK). The DB
-- hit on a fresh row is one statement per piece - cheaper than re-parsing
-- JSON - and the result is positive: a row exists, so the price applies
-- verbatim, no fallback chain needed by callers.
-- ----------------------------------------------------------------------------

Price = Price or {}

--- Look up a per-(drawable, texture) override. Returns the row's price, or
--- nil when no row matches. nil signals "no DB opinion, fall back".
function Price.fromDb(kind, slotId, collection, drawable, texture)
  if kind ~= 'component' and kind ~= 'prop' then return nil end
  if type(slotId) ~= 'number' or slotId < 0 or slotId > 255 then return nil end
  if type(drawable) ~= 'number' or drawable < 0 then return nil end
  if type(texture) ~= 'number' or texture < 0 then return nil end
  if type(collection) ~= 'string' or collection == '' then return nil end

  local row = Db.one([[
    SELECT price
      FROM clothing_prices
     WHERE kind = ? AND slot_id = ? AND collection = ? AND drawable = ? AND texture = ?
     LIMIT 1
  ]], {
    kind, tostring(slotId), collection,
    tostring(drawable), tostring(texture),
  }, 'price:lookup')

  if row == nil then return nil end
  return tonumber(row.price)
end

--- Set a per-(drawable, texture) price. Used by admin tooling - not by
--- gameplay code. Returns true on success, false when the row's price was
--- not a non-negative integer.
function Price.set(kind, slotId, collection, drawable, texture, price)
  if kind ~= 'component' and kind ~= 'prop' then return false, 'bad kind' end
  if type(slotId) ~= 'number' or slotId < 0 or slotId > 255 then return false, 'bad slot' end
  if type(drawable) ~= 'number' or drawable < 0 then return false, 'bad drawable' end
  if type(texture) ~= 'number' or texture < 0 then return false, 'bad texture' end
  if type(collection) ~= 'string' or collection == '' then return false, 'bad collection' end

  price = math.floor(tonumber(price) or -1)
  if price < 0 then return false, 'bad price' end

  Db.update([[
    INSERT INTO clothing_prices
      (kind, slot_id, collection, drawable, texture, price)
    VALUES (?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE price = VALUES(price)
  ]], {
    kind, tostring(slotId), collection,
    tostring(drawable), tostring(texture),
    tostring(price),
  }, 'price:set')

  return true
end

--- Drop an override. Useful when the Lua default is "better than the row"
--- and staff wants the file's number to win again.
function Price.clear(kind, slotId, collection, drawable, texture)
  if kind ~= 'component' and kind ~= 'prop' then return false end
  if type(slotId) ~= 'number' or slotId < 0 or slotId > 255 then return false end
  if type(drawable) ~= 'number' or drawable < 0 then return false end
  if type(texture) ~= 'number' or texture < 0 then return false end
  if type(collection) ~= 'string' or collection == '' then return false end

  Db.update([[
    DELETE FROM clothing_prices
     WHERE kind = ? AND slot_id = ? AND collection = ? AND drawable = ? AND texture = ?
  ]], {
    kind, tostring(slotId), collection,
    tostring(drawable), tostring(texture),
  }, 'price:clear')

  return true
end

print(('[%s] owned module ready'):format(RESOURCE))
