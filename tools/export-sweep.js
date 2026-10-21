#!/usr/bin/env node
/**
 * export-sweep — every cross-resource export call, checked against the
 * resource it points at.
 *
 * WHY THIS EXISTS
 *
 * `exports['nifty-inventory']:grantStartingItems(...)` on a resource that
 * defines the function but does not EXPORT it is a nil call at runtime, and
 * the server says so once, in a line nobody reads:
 *
 *     SCRIPT ERROR: @nifty-world/server/sv_main.lua:129:
 *       No such export grantStartingItems in resource nifty-inventory
 *
 * It cost a character their phone and their ID card, because that is what the
 * missing export hands out - and the character still entered the world.
 *
 * The same shape with a `:` instead of a `.` shifts every argument by one,
 * which is a different bug with the same silence. The colon is checked here
 * too, because it is the one that is right.
 *
 * THE SPELLING IS NOT A MATTER OF TASTE — IT IS MEASURED
 *
 * On this runtime, an export called through the exports proxy EATS its first
 * argument when it is spelled with a dot. Measured on the server itself, with
 * a probe export that returns everything it receives:
 *
 *     Core.probeArgs('A', 2, true)    ->  n=2 [2 | true]        'A' is GONE
 *     Core:probeArgs('A', 2, true)    ->  n=3 [A | 2 | true]     all three arrive
 *
 * The same for the self-reference (`exports['nifty-shop']`): the dot form
 * loses the first argument there too.
 *
 * So `Inventory.add(characterId, code, 1)` with a dot hands the export
 * (code, 1) — the character id becomes the item code, and the item is written
 * to the wrong place or to nowhere. Nothing errors: the call succeeds, with
 * the wrong arguments.
 *
 * The dot is right for a PLAIN TABLE (the facade's fields), and wrong for the
 * exports proxy. Those are different things, and the difference is one
 * argument wide.
 *
 * HOW TO RUN
 *
 *   node tools/export-sweep.js
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', 'resources', '[nifty]');

/**
 * Resources that are NOT part of this project.
 *
 * They are downloaded, not authored, and they are deliberately not tracked
 * (see .gitignore). A call into one of them cannot be checked here - the
 * question "does this resource export that" has an answer outside the
 * repository, and the answer is not ours to give.
 */
const EXTERNAL = new Set([
  'spawnmanager', 'mapmanager', 'sessionmanager', 'oxmysql', 'ox_lib',
  'ox_target', 'chat', 'myphone', 'lb-phone', 'hardcap', 'bob74_ipl',
]);

/**
 * Comments are not code.
 *
 * STRINGS ARE LEFT ALONE, and that is deliberate: the name of an export IS a
 * string, so stripping strings would strip the very thing being looked for.
 */
function strip(src) {
  return src
    .replace(/--\[\[[\s\S]*?\]\]/g, ' ')
    .replace(/--[^\n]*/g, ' ');
}

const resources = fs.readdirSync(ROOT, { withFileTypes: true })
  .filter((e) => e.isDirectory())
  .map((e) => e.name);

/** Every export a resource offers, client and server separately. */
const offered = new Map();
for (const name of resources) {
  const dir = path.join(ROOT, name);
  const set = { client: new Set(), server: new Set() };
  for (const kind of ['client', 'server', 'shared']) {
    const sub = path.join(dir, kind);
    if (!fs.existsSync(sub)) continue;
    for (const e of fs.readdirSync(sub, { withFileTypes: true })) {
      if (!e.isFile() || !e.name.endsWith('.lua')) continue;
      const src = fs.readFileSync(path.join(sub, e.name), 'utf8');
      for (const m of src.matchAll(/exports\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]/g)) {
        set[kind === 'shared' ? 'server' : kind].add(m[1]);
      }
    }
  }
  offered.set(name, set);
}

/** The files of a resource, with the side they run on. */
function filesOf(name) {
  const dir = path.join(ROOT, name);
  const out = [];
  for (const kind of ['client', 'server', 'shared']) {
    const sub = path.join(dir, kind);
    if (!fs.existsSync(sub)) continue;
    for (const e of fs.readdirSync(sub, { withFileTypes: true })) {
      if (e.isFile() && e.name.endsWith('.lua')) {
        out.push({ file: path.relative(ROOT, path.join(sub, e.name)).replace(/\\/g, '/'), kind, src: strip(fs.readFileSync(path.join(sub, e.name), 'utf8')) });
      }
    }
  }
  return out;
}

let problems = 0;
let calls = 0;

/**
 * The two forms a cross-resource call takes.
 *
 * DIRECT:   exports['nifty-inventory']:add('phone', 1)
 * HANDLE:   local Inv = exports['nifty-inventory']   ...   Inv:add('phone', 1)
 *
 * The HANDLE form is the one that bit: `local Inventory = exports['nifty-inventory']`
 * looked perfectly fine and the export it called did not exist. The handle is
 * not the call - the METHOD on the handle is the call, and only the method
 * name can be checked against what the target resource exports.
 */
const DIRECT = /exports\s*\[\s*['"]([^'"]+)['"]\s*\]\s*(:|\.)\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(/g;

/**
 * A HANDLE is `NAME = exports['resource']` - the proxy itself.
 *
 * It is NOT `NAME = exports['resource']:facade()`: that is a CALL, and what
 * it returns is a plain Lua table, where the dot is the correct spelling and
 * the colon shifts the arguments. The negative lookahead keeps the two apart.
 *
 * Getting this wrong is not a cosmetic mistake: the facade is the one export
 * that hands out a table, and it is spread over every resource's shared
 * core.lua - so a sweep that treats it as a proxy would demand the colon
 * everywhere and break the one form that works.
 */
const HANDLE_DEF = /(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*exports\s*\[\s*['"]([^'"]+)['"]\s*\]\s*(?![:.])/g;

for (const name of resources) {
  for (const { file, kind, src } of filesOf(name)) {
    const side = kind === 'client' ? 'client' : 'server';

    /** The handles of this file: local name -> target resource. */
    const handles = new Map();
    for (const m of src.matchAll(HANDLE_DEF)) {
      handles.set(m[1], m[2]);
    }

    const check = (target, exportName, spelling, where) => {
      calls += 1;

      // THE SPELLING FIRST, because it is wrong either way.
      //
      // The dot form eats the first argument, whether the export exists or
      // not - measured, see the header. The export being missing is a loud
      // error; the wrong spelling is a silent wrong result.
      if (spelling === '.') {
        problems += 1;
        console.log(`  PUNKT  ${file}: "${target}.${exportName}" - der Punkt frisst das erste Argument (${where}), es muss "${target}:${exportName}" heißen`);
      }

      if (target === 'RESOURCE' || target === name) {
        // A self-call: the resource calls its own export. Still worth
        // checking - a missing export on its own resource is the same
        // runtime error, and it is the shape the creator's missing
        // `getItemNames` wrapper had.
        const own = offered.get(name);
        const set = kind === 'shared'
          ? new Set([...own.client, ...own.server])
          : own[side];
        if (!set.has(exportName)) {
          problems += 1;
          console.log(`  SELBST ${file}: die eigene Ressource exportiert "${exportName}" nicht (${side}seitig)`);
        }
        return;
      }

      if (EXTERNAL.has(target)) return;

      if (!offered.has(target)) {
        problems += 1;
        console.log(`  FEHLT  ${file}: die Ressource "${target}" gibt es im Projekt gar nicht`);
        return;
      }

      const tgt = offered.get(target);
      const set = kind === 'shared'
        ? new Set([...tgt.client, ...tgt.server])
        : tgt[side];

      if (set.has(exportName)) return;

      const other = tgt[side === 'client' ? 'server' : 'client'];
      if (other.has(exportName)) {
        problems += 1;
        console.log(`  SEITE  ${file}: "${target}:${exportName}" gibt es, aber nur ${side === 'client' ? 'server' : 'client'}seitig`);
      } else {
        problems += 1;
        console.log(`  FEHLT  ${file}: "${target}:${exportName}" - die Ressource exportiert das nicht (${side}seitig)`);
      }
    };

    // DIRECT: exports['x']:name(
    for (const m of src.matchAll(DIRECT)) {
      check(m[1], m[3], m[2], 'direkt');
    }

    // HANDLE: Inv:name( / Inv.name(  where Inv = exports['x']
    for (const [handle, target] of handles) {
      const escaped = handle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

      const re = new RegExp(
        '\\b' + escaped + '\\s*(:|\\.)\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*\\(',
        'g'
      );
      for (const m of src.matchAll(re)) {
        check(target, m[2], m[1], 'handle');
      }

      // THE VALUE FORM: `Inv.name` WITHOUT a call.
      //
      // Fetching a member of the proxy is harmless by itself - but the fetch
      // hands out the wrapper function, and whoever calls THAT function
      // without the proxy as `self` loses the first argument. `pcall(fn, a)`
      // is exactly that: it was in the phone resource, and it dropped the
      // item code on the floor.
      //
      // A `type(...)` check is exempt: it never calls anything. So is a
      // truthiness check (`not Inventory.view`), which only asks whether the
      // export is there at all.
      const valueRe = new RegExp(
        '(?<!type\\()(?<!not )\\b' + escaped + '\\s*\\.\\s*([A-Za-z_][A-Za-z0-9_]*)\\b\\s*(?!\\()',
        'g'
      );
      for (const m of src.matchAll(valueRe)) {
        problems += 1;
        console.log(`  RISIKO ${file}: "${target}.${m[1]}" wird als Wert weitergegeben - wenn der Aufrufer den Export ohne den Proxy als self ruft, frisst es das erste Argument`);
      }
    }
  }
}

console.log('');
console.log(`geprüfte Aufrufe: ${calls}, Probleme: ${problems}`);
if (problems === 0) console.log('alles exportiert');
