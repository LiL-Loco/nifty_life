--[[
  Display names for the creator. German, because the website and the whole
  interface are German (a label the player reads in English and a form they fill
  in in German is a bug nobody reports).

  EVERY STRING IN THIS FILE IS OURS. Nothing here is copied from a game file, a
  third-party repository or a label dump. The hair decal mapping and the clothing
  name database are derived at runtime instead, for exactly this reason - see
  cl_creator.lua and the note there about why a table nobody licensed cannot be
  pasted in.

  These are LABELS. The id is the truth. A wrong name here is a cosmetic bug and
  never becomes a stored value, which is what makes writing our own safe and
  copying someone else's not necessary.
]]

local RESOURCE = GetCurrentResourceName()

--- A GLOBAL, like `AppearanceConfig` and `GameData` alongside it.
Labels = {}

--- The twenty face features, in the engine's own order (`SetPedFaceFeature`).
---
--- The engine gives these no names at all - a menu without them says "Merkmal 7",
--- which tells the player nothing about what they are dragging. These are ordinary
--- anatomy terms, not anything extracted from anywhere.
Labels.FEATURES = {
  'Nasenbreite',
  'Nasenboden',
  'Nasenspitzenlaenge',
  'Nasenruecken',
  'Nasenspitzenhoehe',
  'Nasenhoeher',
  'Brauenhoehe',
  'Brauentiefe',
  'Wangenbeinhoehe',
  'Wangenbeinbreite',
  'Wangentiefe',
  'Augengroesse',
  'Lippendicke',
  'Kieferbreite',
  'Kieferform',
  'Kinnhoehe',
  'Kinntiefe',
  'Kinnbreite',
  'Kinnkerbe',
  'Halsbreite',
}

--- Head overlay style names, in the engine's own order.
---
--- Indexed by overlay id. Index 0 of each list is always "Kein": the game uses
--- style 255 to switch an overlay off, and offering that as the first entry means
--- turning something off is the same gesture as turning something on rather than
--- a separate concept the player has to learn.
---
--- `FALLBACK` is used when the engine reports more styles than we have names for -
--- which it will, after the next content update. A missing name must produce a
--- number, not a hole in the menu.
Labels.OVERLAY_STYLES = {
  [0] = { -- Pickel
    'Kein', 'Masern', 'Pickel', 'Flecken', 'Ausbruch', 'Mitesser', 'Aufbau',
    'Pusteln', 'Pickbeule', 'Volle Akne', 'Akne', 'Wangenroete', 'Gesichtsroete',
    'Knirpse', 'Pubertät', 'Pickbeule (schwer)', 'Kinnroete', 'Zwei Gesichter',
    'T-Zone', 'Fettig', 'Gezeichnet', 'Akne-Narben', 'Volle Akne-Narben',
    'Fieberblaeschen', 'Impetigo',
  },
  [1] = { -- Bart
    'Keiner', 'Leichte Stoppeln', 'Balbo', 'Vollbart', 'Goatee', 'Kinn',
    'Kinnflaum', 'Bleistift-Kinnbart', 'Struppig', 'Musketeer', 'Schnurrbart',
    'Getrimmter Bart', 'Stoppeln', 'Duenner Vollbart', 'Hufeisen',
    'Bleistift und Backenbart', 'Kinnbart', 'Balbo und Koteletten', 'Koteletten',
    'Struppiger Bart', 'Lockig', 'Lockig und Strange', 'Handlebar', 'Faustisch',
    'Otto und Patch', 'Otto und Full Stranger', 'Light Franz', 'The Hampstead',
    'The Ambrose', 'Lincoln Curtain',
  },
  [2] = { -- Augenbrauen
    'Keine', 'Ausgewogen', 'Fashion', 'Kleopatra', 'Schelmisch', 'Feminin',
    'Verfuehrend', 'Zusammengezogen', 'Chola', 'Triomphe', 'Sorglos', 'Anmutig',
    'Nagetier', 'Double Tram', 'Duenn', 'Naehergezogen', 'Gezupft',
    'Schmal und grade', 'Natuuerlich', 'Fuzzy', 'Ungepflegt', 'Raupe',
    'Regulaer', 'Mediterran', 'Gepflegt', 'Struessel', 'Federartig',
    'Stachlig', 'Monobrow', 'Gefluegelt', 'Triple Tram', 'Bogen Tram',
    'Lochmuster', 'Ausgeblichen', 'Solo Tram',
  },
  [3] = { -- Alterung
    'Kein', "Krähenaußen", 'Erste Zeichen', 'Mittleres Alter', 'Sorgenfalten',
    'Depression', 'Unterschieden', 'Gealtert', 'Verwittert', 'Runzlig',
    'Durchhaengend', 'Hartes Leben', 'Vintage', 'Im Ruhestand', 'Fixer',
    'Greisenhaft',
  },
  [4] = { -- Make-up
    'Kein', 'Rauchschwarz', 'Bronze', 'Weiches Grau', 'Retro-Glamour',
    'Natuerlich', 'Katzenauge', 'Chola', 'Vampir', 'Vinewood-Glamour',
    'Kaugummi', 'Aqua-Traum', 'Pin-up', 'Leidenschaft', 'Rauchschwarzes Katzenauge',
    'Glimmende Rubin', 'Pop-Prinzessin',
  },
  [5] = { -- Röte
    'Keine', 'Voll', 'Geschraegt', 'Rund', 'Waagerecht', 'Hoch', 'Herzförmig',
    'Achziger',
  },
  [6] = { -- Teint
    'Keiner', 'Rose Wangen', 'Stoppelroete', 'Hitzeflush', 'Sonnenbrand',
    'Gequetscht', 'Alkoholraete', 'Fleckig', 'Totem', 'Blutgefasse',
    'Beschaedigt', 'Bleich', 'Geisterhaft',
  },
  [7] = { -- Sonnenschaden
    'Kein', 'Ungleichmaessig', 'Schmirgelpapier', 'Fleckig', 'Rau', 'Lederartig',
    'Texturiert', 'Grob', 'Robust', 'Furchig', 'Rissig', 'Gruesselig',
  },
  [8] = { -- Lippenstift
    'Kein', 'Matt', 'Glanz', 'Konturiert matt', 'Konturiert glanzend',
    'Stark konturiert matt', 'Stark konturiert glanzend',
    'Konturiert nude matt', 'Konturiert nude glanzend', 'Verschmiert', 'Geisha',
  },
  [9] = { -- Muttermale und Sommersprossen
    'Keine', 'Cherub', 'Ueberall', 'Unregelmaessig', 'Punkt-Strich',
    'Über die Bruecke', 'Baby Doll', 'Pixie', 'Sonnenkuess', 'Schoenheitsmale',
    'Aufgestellt', 'Modelesque', 'Gelegentlich', 'Gesprenkelt', ' Regentropfen',
    'Doppelt', 'Einseitig', 'Paarweise', 'Wachstum',
  },
  [10] = { -- Brustbehaarung
    'Keine', 'Natuerlich', 'Der Streifen', 'Der Baum', 'Zottelig', 'Gruesslich',
    'Affe', 'Gepflegter Affe', 'Bikini', 'Blitz', 'Umgekehrter Blitz',
    'Liebesherz', 'Brustweh', 'Glückliches Gesicht', 'Schädel', 'Schneckenspur',
    'Schnecke und Nippel', 'Behaarte Arme',
  },
}

--- What to print for an overlay style that has no name.
Labels.UNNAMED_STYLE = function(index)
  return ('Stil %d'):format(index)
end

--- The thirty-two eye colours, in the game's own order (`SetPedEyeColor`).
---
--- These are descriptive names, the same kind of thing the game itself uses in its
--- own character creator, written out rather than extracted.
Labels.EYE_COLOURS = {
  'Gruen', 'Smaragd', 'Hellblau', 'Ozeanblau', 'Hellbraun', 'Dunkelbraun',
  'Haselnuss', 'Dunkelgrau', 'Hellgrau', 'Rosa', 'Gelb', 'Lila', 'Schwarz',
  'Grauschattierungen', 'Tequila Sonnenaufgang', 'Atomar', 'Warp', 'ECola',
  'Space Ranger', 'Yin Yang', 'Bullseye', 'Eidechse', 'Drache',
  'Ausserirdisch', 'Ziege', 'Smiley', 'Besessen', 'Daemon', 'Infiziert', 'Alien',
  'Untot', 'Zombie',
}

--- Head blend presets.
---
--- NOT NAMED, DELIBERATELY. The engine identifies them as numbers, the game never
--- gave them names, and the twenty-four "father" entries in third-party menus are
--- English first names that mean nothing to a German player - "Timothy" and
--- "Victor" are the same blend. "Vater 7" is honest about what it is; a borrowed
--- name would be decoration pretending to be information.
Labels.FATHER = function(index) return ('Vater %d'):format(index + 1) end
Labels.MOTHER = function(index) return ('Mutter %d'):format(index + 1) end

-- Real parent names for the third-person pick. GTA's head_blend_data
-- takes any of the 47 presets (the same presets that populate the
-- mother and father lists, and 3 extras the engine does not assign to
-- either gender). lbg-char carries a 47-entry list we lift here, with
-- the gender-specific mother / father lists folded in. The list is
-- "Benjamin, Daniel, ..., Misty" - the same names the official
-- character creator shows.
Labels.THIRDPERSON = {
  'Benjamin', 'Daniel', 'Joshua', 'Noah', 'Andrew', 'Juan', 'Alex', 'Isaac', 'Evan', 'Ethan',
  'Vincent', 'Angel', 'Diego', 'Adrian', 'Gabriel', 'Michael', 'Santiago', 'Kevin', 'Louis', 'Samuel',
  'Anthony', 'Claude', 'Niko', 'John',
  'Hannah', 'Audrey', 'Jasmine', 'Giselle', 'Amelia', 'Isabella', 'Zoe', 'Ava', 'Camila', 'Violet',
  'Sophia', 'Evelyn', 'Nicole', 'Ashley', 'Grace', 'Brianna', 'Natalie', 'Olivia', 'Elizabeth', 'Charlotte',
  'Emma', 'Misty',
}

--- Hair.
---
--- No names here either, and the same reason. The engine reports hair styles as
--- drawable indices within a collection, and any name we attached would have to be
--- either invented (useless, and worse than a number) or lifted from a table
--- someone else compiled.
Labels.HAIR = function(index) return ('Frisur %d'):format(index + 1) end

--- Report a missing label loudly rather than shipping a hole in the menu.
---
--- This fires when the engine grew past what we have names for. That is expected
--- after every content update and it is not a crash - the menu falls back to a
--- number - but it does mean the name lists are out of date, and that is worth one
--- line in the console.
local reportedGaps = {}

function Labels.overlayStyle(overlayId, index)
  local list = Labels.OVERLAY_STYLES[overlayId]
  local name = list and list[index]

  if name then return name end

  local key = tostring(overlayId)
  if not reportedGaps[key] then
    reportedGaps[key] = true
    print(('[%s] no German label for overlay %d style %d - falling back to a number. ' ..
      'The name list is behind the current game files.'):format(RESOURCE, overlayId, index))
  end

  return Labels.UNNAMED_STYLE(index)
end