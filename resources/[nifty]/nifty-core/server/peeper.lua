--- Peeper — the broadcast social layer, and the web↔character binding.
---
--- ADR-0019: a broadcast feed in the Twitter mould. Asymmetric follows, public
--- timeline, replies, likes. A character CANNOT delete their own post; only
--- staff can, and that writes a record rather than removing the row.
---
--- ADR-0022: the same feed is reachable from the website, and that required
--- solving identity before it required any UI. A post is authored by a
--- CHARACTER whichever surface wrote it — there is no "web identity". The
--- binding is proven by a code generated in game and typed on the website, and
--- only this module can complete it, because only this module runs with the
--- privileges that `nifty_website` does not have (see database/grants.sql).
---
--- Everything a client could influence arrives here untrusted: the author is
--- derived from the caller's binding, never from a payload.

local RESOURCE = GetCurrentResourceName()

Peeper = {}

-- ---------------------------------------------------------------------------
-- Web pairing (ADR-0022)
-- ---------------------------------------------------------------------------

-- Ambiguous glyphs are excluded on purpose: this code gets read off a screen
-- and typed on a phone, so O/0 and I/1 are where the mistakes happen.
local CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local CODE_LENGTH = 8

local function randomCode(length)
  local out = {}

  for i = 1, length do
    local pick = math.random(1, #CODE_ALPHABET)
    out[i] = CODE_ALPHABET:sub(pick, pick)
  end

  return table.concat(out)
end

--- SHA-256 rather than `math.random`-seeded nothing — the code is a bearer
--- token for "I am this character", and it is stored hashed so a database dump
--- cannot be replayed against the website.
local function hashCode(code)
  return Db.one('SELECT SHA2(?, 256) AS h', { code }, 'peeper:hash')
end

--- Issue a fresh code for this character. Any previous code is replaced, not
--- merely shadowed: a player who asks for a new one is telling us the old one
--- is compromised, and leaving it valid would be ignoring that.
---
--- @return string|nil code, string|nil error
function Peeper.createPairingCode(characterId)
  if type(characterId) ~= 'string' or characterId == '' then return nil, 'no character' end

  local character = Db.one('SELECT id FROM characters WHERE id = ?', { characterId }, 'peeper:pairingExists')
  if not character then return nil, 'unknown character' end

  local minutes = tonumber(GetSetting('peeper.pairing.ttl_minutes', 15)) or 15
  local code = randomCode(CODE_LENGTH)
  local hash = hashCode(code)

  if not hash then return nil, 'could not hash code' end

  -- One live code per character. The primary key makes the insert an upsert, so
  -- a second call cannot leave two valid codes behind.
  Db.update([[
    INSERT INTO web_pairing_codes (character_id, code_hash, expires_at)
    VALUES (?, ?, DATE_ADD(NOW(), INTERVAL ? MINUTE))
    ON DUPLICATE KEY UPDATE
      code_hash  = VALUES(code_hash),
      created_at = NOW(),
      expires_at = VALUES(expires_at)
  ]], { characterId, hash.h, minutes }, 'peeper:pairingUpsert')

  print(('[%s] pairing code issued for %s, valid %d min'):format(RESOURCE, characterId, minutes))

  return code, nil
end

--- Which character, if any, a Discord login is bound to.
--- @return string|nil characterId
function Peeper.characterForDiscord(discordId)
  if type(discordId) ~= 'string' or discordId == '' then return nil end

  local row = Db.one('SELECT character_id FROM web_links WHERE discord_id = ?', { discordId }, 'peeper:lookup')
  return row and row.character_id or nil
end

function Peeper.isLinked(discordId)
  return Peeper.characterForDiscord(discordId) ~= nil
end

--- Process everything the website has submitted.
---
--- Runs on a timer, which means it runs only while the game server is up
--- (ADR-0010 — frozen Monday to Thursday). That is a real constraint and the
--- website has to state it: a pairing request made midweek is accepted on
--- Friday, not immediately.
---
--- Every submitted request is consumed, whether it matched or not. Leaving a
--- wrong code in the table would let an attacker keep guessing against a
--- growing pile of attempts; one shot per request, rate limiting on the web.
---
--- @return number linked, number rejected
function Peeper.redeemRequests()
  local requests = Db.all(
    'SELECT id, discord_id, code FROM web_link_requests ORDER BY id LIMIT 50',
    {}, 'peeper:redeem')

  local linked, rejected = 0, 0

  for _, request in ipairs(requests) do
    local hash = hashCode(request.code)
    local match = nil

    if hash then
      match = Db.one([[
        SELECT character_id FROM web_pairing_codes
         WHERE code_hash = ? AND expires_at > NOW()
      ]], { hash.h }, 'peeper:redeemMatch')
    end

    if match and Peeper.characterForDiscord(request.discord_id) == nil then
      local inserted = Db.insert(
        'INSERT INTO web_links (discord_id, character_id) VALUES (?, ?)',
        { request.discord_id, match.character_id }, 'peeper:link')

      if inserted then
        -- The code is single-use. Leaving it would let the same code link a
        -- second Discord account to the same character.
        Db.update('DELETE FROM web_pairing_codes WHERE character_id = ?',
          { match.character_id }, 'peeper:linkBurnCode')
        linked = linked + 1
      else
        rejected = rejected + 1
      end
    else
      rejected = rejected + 1
    end

    Db.update('DELETE FROM web_link_requests WHERE id = ?', { request.id }, 'peeper:redeemConsume')
  end

  if linked > 0 or rejected > 0 then
    print(('[%s] pairing: %d linked, %d rejected'):format(RESOURCE, linked, rejected))
  end

  return linked, rejected
end

--- Whether this character may act as staff (ADR-0019). Separate from jobs on
--- purpose: the police department is not the moderation team.
function Peeper.isStaff(characterId)
  local row = Db.one('SELECT is_staff FROM characters WHERE id = ?', { characterId }, 'peeper:isStaff')
  -- TINYINT arrives as a string, so `row.is_staff == 1` is false (LEARNINGS.md).
  return row ~= nil and Db.money.toNumber(row.is_staff) == 1
end

-- ---------------------------------------------------------------------------
-- Posting
-- ---------------------------------------------------------------------------

--- Every author name is SNAPSHOT, not a join. The website must be able to render
--- a post without any access to `characters`, and a post should read as the name
--- it was published under.
local function displayName(characterId)
  local row = Db.one(
    'SELECT first_name, last_name FROM characters WHERE id = ?', { characterId }, 'peeper:name')

  if not row then return nil end

  local parts = {}
  if type(row.first_name) == 'string' and row.first_name ~= '' then parts[#parts + 1] = row.first_name end
  if type(row.last_name) == 'string' and row.last_name ~= '' then parts[#parts + 1] = row.last_name end

  if #parts == 0 then return nil end
  return table.concat(parts, ' ')
end

local function publish(characterId, parentId, body, placeName, source)
  if type(body) ~= 'string' then return nil, 'bad request' end

  local trimmed = body:match('^%s*(.-)%s*$')
  if trimmed == '' then return nil, 'empty post' end

  local maxLength = tonumber(GetSetting('peeper.post.max_length', 280)) or 280
  if #trimmed > maxLength then
    trimmed = trimmed:sub(1, maxLength)
  end

  local name = displayName(characterId)
  if not name then return nil, 'unknown character' end

  -- Places are an attribute on the post, never a location history (ADR-0019).
  local place = nil
  if placeName ~= nil then
    if type(placeName) ~= 'string' then return nil, 'bad place' end
    place = placeName:match('^%s*(.-)%s*$')
    if place == '' then place = nil
    elseif #place > 64 then place = place:sub(1, 64) end
  end

  local id = Nifty.newUuid()

  -- `parentId` is nil for a top-level post and `place` is nil for one without a
  -- Place. A nil inside a Lua table destroys the table's length, so this INSERT
  -- would arrive with six values for seven placeholders — see LEARNINGS.md, this
  -- is the fourth time in this project that exact trap has been rebuilt. NULLIF
  -- plus `or ''` is the established fix.
  local inserted = Db.insert([[
    INSERT INTO peeper_posts (id, author_character, author_name, parent_id, body, place_name, source)
    VALUES (?, ?, ?, NULLIF(?, ''), ?, NULLIF(?, ''), ?)
  ]], { id, characterId, name, parentId or '', trimmed, place or '', source }, 'peeper:post')

  if inserted == nil then return nil, 'could not post' end

  return id, nil
end

--- @param source 'game' | 'web'. Passed by the caller, never by the client:
--- a client cannot claim its post came from the website or vice versa.
function Peeper.post(characterId, body, placeName, source)
  return publish(characterId, nil, body, placeName, source or 'game')
end

--- A reply must point at something real and not already removed — replying to a
--- deleted post would put content back into a feed staff deliberately cleaned.
function Peeper.reply(characterId, parentId, body, source)
  if type(parentId) ~= 'string' or parentId == '' then return nil, 'bad request' end

  local parent = Db.one(
    'SELECT id FROM peeper_posts WHERE id = ? AND deleted_at IS NULL', { parentId }, 'peeper:replyTarget')

  if not parent then return nil, 'unknown post' end

  return publish(characterId, parentId, body, nil, source or 'game')
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

--- The public timeline. Deleted rows are filtered in SQL rather than by the
--- caller — a filter that lives in application code is one forgettable line away
--- from showing a deleted post again.
function Peeper.feed(limit, offset)
  local page = tonumber(limit) or tonumber(GetSetting('peeper.feed.page_size', 25)) or 25
  page = math.min(math.max(page, 1), 100)

  return Db.all([[
    SELECT p.id, p.author_character, p.author_name, p.parent_id, p.body,
           p.place_name, p.source, p.created_at,
           (SELECT COUNT(*) FROM peeper_likes l WHERE l.post_id = p.id) AS like_count,
           (SELECT COUNT(*) FROM peeper_posts r WHERE r.parent_id = p.id AND r.deleted_at IS NULL) AS reply_count
      FROM peeper_posts p
     WHERE p.deleted_at IS NULL
     ORDER BY p.created_at DESC, p.id DESC
     LIMIT ? OFFSET ?
  ]], { page, math.max(tonumber(offset) or 0, 0) }, 'peeper:feed')
end

function Peeper.replies(postId)
  if type(postId) ~= 'string' then return {} end

  return Db.all([[
    SELECT p.id, p.author_character, p.author_name, p.body, p.created_at
      FROM peeper_posts p
     WHERE p.parent_id = ? AND p.deleted_at IS NULL
     ORDER BY p.created_at ASC
  ]], { postId }, 'peeper:replies')
end

function Peeper.postsBy(characterId, limit, offset)
  local page = math.min(math.max(tonumber(limit) or 25, 1), 100)

  return Db.all([[
    SELECT id, body, place_name, source, created_at
      FROM peeper_posts
     WHERE author_character = ? AND parent_id IS NULL AND deleted_at IS NULL
     ORDER BY created_at DESC
     LIMIT ? OFFSET ?
  ]], { characterId, page, math.max(tonumber(offset) or 0, 0) }, 'peeper:postsBy')
end

-- ---------------------------------------------------------------------------
-- Engagement
-- ---------------------------------------------------------------------------

function Peeper.like(characterId, postId)
  local post = Db.one(
    'SELECT id FROM peeper_posts WHERE id = ? AND deleted_at IS NULL', { postId }, 'peeper:likeTarget')
  if not post then return false end

  -- Idempotent: liking twice is not an error, it is the same like.
  Db.insert('INSERT IGNORE INTO peeper_likes (post_id, character_id) VALUES (?, ?)',
    { postId, characterId }, 'peeper:like')
  return true
end

function Peeper.unlike(characterId, postId)
  local affected = Db.update(
    'DELETE FROM peeper_likes WHERE post_id = ? AND character_id = ?', { postId, characterId }, 'peeper:unlike')
  return affected ~= nil and affected > 0
end

--- Asymmetric by construction (ADR-0019). The CHECK on the table is what stops
--- a self-follow; this pre-check only returns a sentence instead of a constraint
--- violation.
function Peeper.follow(characterId, targetId)
  if type(targetId) ~= 'string' or targetId == '' then return false, 'bad request' end
  if targetId == characterId then return false, 'you already follow yourself' end

  local target = Db.one('SELECT id FROM characters WHERE id = ?', { targetId }, 'peeper:followTarget')
  if not target then return false, 'unknown character' end

  Db.insert('INSERT IGNORE INTO peeper_follows (follower, followee) VALUES (?, ?)',
    { characterId, targetId }, 'peeper:follow')

  return true, nil
end

function Peeper.unfollow(characterId, targetId)
  local affected = Db.update(
    'DELETE FROM peeper_follows WHERE follower = ? AND followee = ?', { characterId, targetId }, 'peeper:unfollow')
  return affected ~= nil and affected > 0
end

--- Posts from the people this character follows. An empty timeline for a new
--- character is the correct state, not a bug — there is nothing to show yet.
function Peeper.timeline(characterId, limit, offset)
  local page = math.min(math.max(tonumber(limit) or 25, 1), 100)

  return Db.all([[
    SELECT p.id, p.author_character, p.author_name, p.body, p.place_name, p.source, p.created_at
      FROM peeper_follows f
      JOIN peeper_posts p ON p.author_character = f.followee
     WHERE f.follower = ? AND p.deleted_at IS NULL
     ORDER BY p.created_at DESC
     LIMIT ? OFFSET ?
  ]], { characterId, page, math.max(tonumber(offset) or 0, 0) }, 'peeper:timeline')
end

-- ---------------------------------------------------------------------------
-- Moderation (ADR-0019)
-- ---------------------------------------------------------------------------

--- Reports point at a POST, never at a person. "Report this character" cannot be
--- actioned by a staff search; "report this post" is content with an author and a
--- timestamp attached.
function Peeper.report(reporterId, postId, reason)
  if type(postId) ~= 'string' or postId == '' then return nil, 'bad request' end

  local allowed = { spam = true, harassment = true, impersonation = true, other = true }
  if not allowed[reason] then return nil, 'unknown reason' end

  local post = Db.one('SELECT id, author_character FROM peeper_posts WHERE id = ?', { postId }, 'peeper:reportTarget')
  if not post then return nil, 'unknown post' end

  if post.author_character == reporterId then return nil, 'cannot report yourself' end

  local id = Nifty.newUuid()

  local inserted = Db.insert([[
    INSERT INTO peeper_reports (id, reporter, post_id, reason) VALUES (?, ?, ?, ?)
  ]], { id, reporterId, postId, reason }, 'peeper:report')

  if inserted == nil then return nil, 'could not file report' end

  return id, nil
end

function Peeper.openReports(limit)
  local page = math.min(math.max(tonumber(limit) or 25, 1), 100)

  return Db.all([[
    SELECT r.id, r.reason, r.status, r.created_at, r.post_id,
           p.author_character, p.author_name, p.body
      FROM peeper_reports r
      JOIN peeper_posts p ON p.id = r.post_id
     WHERE r.status = 'open'
     ORDER BY r.created_at ASC
     LIMIT ?
  ]], { page }, 'peeper:openReports')
end

--- Staff only. This is the write ADR-0019 calls for and the one thing on this
--- table the author may never do to themselves.
---
--- SOFT DELETE. The row stays, because ADR-0019 wants the decision recorded and
--- because the grant set gives no application user a DELETE on this table at
--- all — the ability to erase a post is not something the database offers.
function Peeper.deletePost(actorId, postId, reason)
  if not Peeper.isStaff(actorId) then return false, 'not staff' end
  if type(postId) ~= 'string' or postId == '' then return false, 'bad request' end

  local post = Db.one(
    'SELECT id FROM peeper_posts WHERE id = ? AND deleted_at IS NULL', { postId }, 'peeper:deleteTarget')

  if not post then return false, 'unknown or already deleted' end

  local affected = Db.update([[
    UPDATE peeper_posts SET deleted_at = NOW(), deleted_by = ?, deleted_reason = ?
     WHERE id = ? AND deleted_at IS NULL
  ]], { actorId, (type(reason) == 'string' and reason:sub(1, 255)) or '', postId }, 'peeper:delete')

  if affected == nil or affected == 0 then return false, 'delete failed' end

  print(('[%s] post %s deleted by %s'):format(RESOURCE, postId, actorId))
  return true, nil
end

function Peeper.resolveReport(reportId, status, note)
  local allowed = { actioned = true, dismissed = true }
  if not allowed[status] then return false, 'bad status' end
  if type(reportId) ~= 'string' then return false, 'bad request' end

  local affected = Db.update([[
    UPDATE peeper_reports SET status = ?, resolved_at = NOW(), resolution_note = ?
     WHERE id = ? AND status = 'open'
  ]], { status, (type(note) == 'string' and note:sub(1, 255)) or '', reportId }, 'peeper:resolveReport')

  return affected ~= nil and affected > 0
end

--- Staff search. With permanent, admin-only deletion and one moderator, the
--- ONLY way a problem reaches staff is a report — so this is what makes a report
--- actionable at all (ADR-0019).
---
--- Every filter is optional and they compose, so "what did this character post
--- in March" is one query rather than a scroll through six months of timeline.
function Peeper.searchPosts(filter)
  filter = filter or {}

  local characterId = nil
  if filter.characterId ~= nil and filter.characterId ~= '' then
    if type(filter.characterId) ~= 'string' then return nil, 'bad character' end
    characterId = filter.characterId
  end

  local keyword = nil
  if filter.keyword ~= nil and filter.keyword ~= '' then
    if type(filter.keyword) ~= 'string' then return nil, 'bad keyword' end
    -- `%` and `_` are LIKE wildcards. `[%%_]` and not `[%_%]`: inside a
    -- character class `%_` is the escaped underscore class, and the following
    -- `%]` is read as a literal `]`, so the set never closes and Lua raises
    -- "malformed pattern (missing ']')". `%%` is the literal percent sign.
    -- `%%%0` re-inserts the matched character — there is no capture group here.
    keyword = filter.keyword:gsub('[%%_]', '%%%0')
  end

  local from, to = nil, nil
  if filter.from ~= nil and filter.from ~= '' then
    from = tostring(filter.from)
  end
  if filter.to ~= nil and filter.to ~= '' then
    to = tostring(filter.to)
  end

  local includeDeleted = filter.includeDeleted == true

  -- Every optional filter goes through NULLIF(?, '') and a value that is never
  -- nil. A nil anywhere in a Lua parameter table truncates it, and a search with
  -- three unset filters would hand MariaDB a different number of values than it
  -- has placeholders — which is the fifth time this project has been bitten by
  -- that exact trap. See LEARNINGS.md.
  local sql = [[
    SELECT p.id, p.author_character, p.author_name, p.body, p.source,
           p.created_at, p.deleted_at, p.deleted_by, p.deleted_reason,
           c.first_name AS author_first, c.last_name AS author_last
      FROM peeper_posts p
      LEFT JOIN characters c ON c.id = p.author_character
     WHERE (NULLIF(?, '') IS NULL OR p.author_character = NULLIF(?, ''))
       AND (NULLIF(?, '') IS NULL OR p.body LIKE CONCAT('%', NULLIF(?, ''), '%'))
       AND (NULLIF(?, '') IS NULL OR p.created_at >= NULLIF(?, ''))
       AND (NULLIF(?, '') IS NULL OR p.created_at <= NULLIF(?, ''))
       AND (NULLIF(?, '') = '1' OR p.deleted_at IS NULL)
     ORDER BY p.created_at DESC
     LIMIT 200
  ]]

  local ok, result = pcall(function()
    return Db.all(sql, {
      characterId or '', characterId or '',
      keyword or '', keyword or '',
      from or '', from or '',
      to or '', to or '',
      includeDeleted and '1' or '',
    }, 'peeper:search')
  end)

  if not ok then
    print(('[%s] peeper search failed: %s'):format(RESOURCE, tostring(result)))
    return nil, 'search failed'
  end

  return result, nil
end

exports('isLinked', Peeper.isLinked)
exports('characterForDiscord', Peeper.characterForDiscord)
exports('feed', Peeper.feed)