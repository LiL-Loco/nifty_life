fx_version 'cerulean'
game 'gta5'

name 'nifty-creator'
author 'Nifty Life 2.0'
description 'Character creation: the allowlist, the creator UI and what the player picks (ADR-0017).'
version '0.1.0'

-- WHAT LIVES WHERE, AND WHY IT IS NOT ALL HERE
--
-- The validation rules and the appearance allowlist moved BACK to nifty-core
-- during the split, and that is not tidiness — it is a cycle they would otherwise
-- have created. `Identity.createCharacter` validates the name, the date of birth,
-- the gender, the appearance and the spawn point BEFORE writing a row. Put those
-- rules in this resource and nifty-core would have to reach into nifty-creator,
-- while nifty-creator already needs nifty-core for the database. Two resources
-- that each need the other to have started is a boot order with no valid first
-- element.
--
-- The split of responsibility that survives is:
--   nifty-core      what is LEGAL (validate.lua, appearance_config.lua)
--   nifty-creator   what is OFFERED and what the player CHOOSES (this resource)
--
-- which is exactly what ADR-0017 asked for in the first place — one file the
-- server enforces cannot drift from the one the UI offers, because there is only
-- one. The creator renders the allowlist it is handed; it does not define it.

shared_scripts {
  'shared/core.lua',
  '@nifty-core/shared/constants.lua',
}

-- NO ui_page HERE. ON PURPOSE.
--
-- The creator's interface is the menu framework (ADR-0023). It borrows the single
-- menu surface from `nifty-ui` through exports, so this resource draws nothing of
-- its own — and a resource with a `ui_page` would be a second focus owner, which
-- is the exact thing the broker exists to prevent.
--
-- WHAT LIVES WHERE. The identity half of a character — name, gender, date of birth,
-- birthplace — is entered on the WEBSITE, not here. This resource is appearance
-- only: clothing, accessories, face and colour. The character row already exists
-- when this opens, and `appearance IS NULL` is what says it has not been finished.
--
-- So there are no text fields here, and `nifty-ui`'s input row is not used by the
-- creator. It exists for other menus — a shop search box, an admin rename — not
-- because of this screen.

-- The data folder is loaded BY THE SCRIPT, not by the manifest's shared_scripts.
-- It is nearly 8 MB of item names, restriction tags and torso mappings, and
-- decoding all of it at boot would cost every player who never opens a menu.
-- `cl_gamedata.lua` reads each file the first time something actually needs it.
files {
  'data/*.json',
  'data/tattoos/*.json'
}

client_scripts {
  'client/cl_labels.lua',
  'client/cl_gamedata.lua',
  'client/cl_creator.lua',
}

-- No server_script. Creating a character is now the website's job, through
-- create_character_from_web (migration 021); what is left here is appearance,
-- which the game server validates against AppearanceConfig and this resource only
-- offers.

dependencies {
  'nifty-core',
  'nifty-ui',
}
lua54 'yes'
