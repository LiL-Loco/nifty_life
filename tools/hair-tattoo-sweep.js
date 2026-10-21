#!/usr/bin/env node
/**
 * hair-tattoo-sweep — the assumptions behind the hair overlay, checked against
 * the data files.
 *
 * WHY THIS EXISTS
 *
 * The creator resolves the hair overlay - the decal the game draws over a
 * hairstyle, the fading and the colour gradient - from `data/<gender>_hair.json`:
 * every row carries `HairTattooCollection` and `HairTattooOverlay`, the two
 * hashes `_SET_PED_FACIAL_DECORATION` needs.
 *
 * That replaced a runtime probe of the tattoo shop, which could never work:
 * `GET_TATTOO_SHOP_DLC_ITEM_DATA` takes a POINTER to a struct that Lua cannot
 * build, and the C# helper `GetTattooCollectionData` does not exist in the
 * runtime at all. The probe failed on every session, the overlay was never
 * applied, and the hair had no fading.
 *
 * A probe that fails is visible. A lookup against data that is shaped
 * differently than the code expects is not - it answers nil, the overlay stays
 * away, and the log says nothing. So the shape is checked here, against the
 * files themselves.
 *
 * WHAT IS CHECKED
 *
 *   1. Both hair files exist and parse.
 *   2. The outer key is the GLOBAL drawable, the inner key the texture - the
 *      same shape the names and the tags use.
 *   3. Every row has GXT, Localized, HairTattooCollection and
 *      HairTattooOverlay.
 *   4. The two hashes are either BOTH -1 (this hairstyle has no tattoo) or
 *      both real hashes. One -1 and one hash would be a row nobody can read.
 *   5. The collection hash is shared by every hairstyle of the same set - the
 *      GXT prefix. That is what makes the field a COLLECTION and not a copy
 *      of something else.
 *   6. The same hairstyle in two drawable ranges carries the same hashes.
 *
 * Not an error, but counted: an overlay hash that two GXT names share means
 * the same cut in two sets - the same decal, two names.
 *
 * HOW TO RUN
 *
 *   node tools/hair-tattoo-sweep.js
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', 'resources', '[nifty]', 'nifty-creator', 'data');

let problems = 0;
let rows = 0;
let withTattoo = 0;
let duplicates = 0;
let sharedOverlays = 0;

function problem(message) {
  problems += 1;
  console.log(`  FEHLER  ${message}`);
}

/** The set a hairstyle belongs to: the GXT name up to its last number. */
function setOf(gxt) {
  const m = /^([A-Z0-9_]*?)_(\d+)$/.exec(gxt || '');
  return m ? m[1] : gxt;
}

const seenGxt = new Map();

for (const gender of ['male', 'female']) {
  const file = path.join(ROOT, `${gender}_hair.json`);

  if (!fs.existsSync(file)) {
    problem(`${gender}_hair.json fehlt`);
    continue;
  }

  let data;
  try {
    data = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    problem(`${gender}_hair.json ist kein gültiges JSON: ${e.message}`);
    continue;
  }

  /** global drawable -> collection hash, per set. */
  const collectionsPerSet = new Map();
  /** overlay hash -> the hairstyle that owns it. */
  const overlayOwner = new Map();

  let genderRows = 0;
  let genderWithTattoo = 0;

  for (const global of Object.keys(data)) {
    if (!/^\d+$/.test(global)) {
      problem(`${gender}: der äußere Schlüssel "${global}" ist keine Zahl (er müsste der globale Drawable sein)`);
      continue;
    }

    const textures = data[global];
    for (const texture of Object.keys(textures)) {
      const entry = textures[texture];
      genderRows += 1;

      for (const field of ['GXT', 'Localized', 'HairTattooCollection', 'HairTattooOverlay']) {
        if (entry[field] === undefined) {
          problem(`${gender} ${global}/${texture}: "${field}" fehlt`);
        }
      }

      const collection = entry.HairTattooCollection;
      const overlay = entry.HairTattooOverlay;

      if (!Number.isInteger(collection) || !Number.isInteger(overlay)) {
        problem(`${gender} ${global}/${texture}: die Hashes sind keine ganzen Zahlen (${collection}, ${overlay})`);
        continue;
      }

      // -1 means "this hairstyle has no tattoo" - in BOTH fields.
      if (collection === -1 && overlay === -1) continue;
      if (collection === -1 || overlay === -1) {
        problem(`${gender} ${global}/${texture}: nur einer der beiden Hashes ist -1 (${collection}, ${overlay})`);
        continue;
      }

      if (collection === 0 || overlay === 0) {
        problem(`${gender} ${global}/${texture}: einer der Hashes ist 0 (${collection}, ${overlay})`);
        continue;
      }

      genderWithTattoo += 1;

      // The same hairstyle can appear in TWO drawable ranges - the freemode
      // ped's hair component holds the same cut more than once (in different
      // sets). That is not a defect; what must hold is that both copies carry
      // the same hashes. A duplicate that disagrees would mean the lookup
      // answers differently depending on which range the player picked.
      const key = `${gender}:${entry.GXT}`;
      const firstSeen = seenGxt.get(key);
      if (firstSeen) {
        duplicates += 1;
        if (firstSeen.collection !== collection || firstSeen.overlay !== overlay) {
          problem(`${gender} ${global}/${texture}: "${entry.GXT}" steht auch bei ${firstSeen.at}, aber mit anderen Hashes (${firstSeen.collection}/${firstSeen.overlay} gegen ${collection}/${overlay})`);
        }
      } else {
        seenGxt.set(key, { at: `${global}/${texture}`, collection, overlay });
      }

      // The collection is shared by the whole set.
      const set = setOf(entry.GXT);
      const known = collectionsPerSet.get(set);
      if (known === undefined) {
        collectionsPerSet.set(set, collection);
      } else if (known !== collection) {
        problem(`${gender} ${global}/${texture}: die Frisuren der Gruppe "${set}" haben verschiedene Collections (${known} und ${collection})`);
      }

      // The overlay is a DECAL, and two GXT names may point at the same decal:
      // the same cut in two sets ("CLO_S1F_H_3_0" and "CLO_S2F_H_0_0") shares
      // one overlay, and so do two names for one hairstyle in different
      // ranges. The lookup is by (global, texture), so it stays unambiguous -
      // but it is worth knowing how often it happens.
      const owner = overlayOwner.get(overlay);
      if (owner && owner.gxt !== entry.GXT) {
        sharedOverlays += 1;
      }
      overlayOwner.set(overlay, { at: `${gender} ${global}/${texture}`, gxt: entry.GXT });
    }
  }

  rows += genderRows;
  withTattoo += genderWithTattoo;

  console.log(`  ${gender}: ${genderRows} Frisuren, davon ${genderWithTattoo} mit Haartattoo, ${collectionsPerSet.size} Gruppen`);
}

console.log('');
console.log(`geprüfte Zeilen: ${rows}, davon mit Tattoo: ${withTattoo}, doppelte Frisuren: ${duplicates}, geteilte Overlays: ${sharedOverlays}, Probleme: ${problems}`);
if (problems === 0) console.log('die Daten tragen die Annahmen');
