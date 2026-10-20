#!/usr/bin/env node
/**
 * native-sweep — which natives does this project call that the runtime does
 * not have?
 *
 * WHY THIS EXISTS
 *
 * A native that does not exist, called behind a `type(...) == 'function'`
 * guard, does not raise. The guard does exactly what it was written to do:
 * it falls through. The code behind it then uses a fallback that is not the
 * one the author intended, and the symptom is somewhere else entirely.
 *
 * Three real instances of that, all found by this tool's predecessor (a
 * hand-written grep) and all fixed:
 *
 *   - `GetNumberOfPedComponentTextures` / `GetNumberOfPedPropTextures`
 *     do not exist. The engine calls them `GetNumberOfPedTextureVariations`
 *     and `GetNumberOfPedPropTextureVariations`. The clamp did nothing, so
 *     the texture came from the collection count and the engine refused the
 *     slot: "CPed::SetVariation: Invalid variation".
 *   - `SetPedHairColor` / `SetPedEyeColor` in the creator: the runtime
 *     spells these with a leading underscore on some builds. One call was
 *     unguarded (a crash), the other was guarded (a silent no-op).
 *   - `GetScaleformMovieHandle` does not exist; `RequestScaleformMovie`
 *     RETURNS the handle. The countdown and the win banner never appeared.
 *
 * WHAT IT IS NOT
 *
 * This is a TRIAGE LIST, not a verdict. The database it compares against
 * (https://runtime.fivem.net/doc/natives.json) is the DOCUMENTED subset of
 * the runtime's natives, and the runtime has more than that:
 *
 *   - the CFX Lua builtins (CreateThread, SendNUIMessage, SetNuiFocus, ...)
 *     are not game natives and are not in the database at all;
 *   - the collection family (SET_PED_COLLECTION_COMPONENT_VARIATION and
 *     friends) is real, works at runtime, and is not documented - it was
 *     MEASURED working, because the engine printed its own errors when it
 *     was called with a bad texture.
 *
 * So a name on this list is a QUESTION, not a defect. Each one has to be
 * checked against the runtime before it is called wrong.
 *
 * HOW TO RUN
 *
 *   node tools/native-sweep.js
 *
 * The database is downloaded to the OS temp directory on first use and reused
 * afterwards. Pass a path to use a different copy:
 *
 *   node tools/native-sweep.js path/to/natives.json
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const https = require('https');

const DB_URL = 'https://runtime.fivem.net/doc/natives.json';
const ROOT = path.resolve(__dirname, '..', 'resources', '[nifty]');

function toSnake(name) {
  return name
    .replace(/_/g, '')
    .replace(/([a-zA-Z])([0-9])/g, '$1_$2')
    .replace(/([0-9])([a-zA-Z])/g, '$1_$2')
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .toUpperCase();
}

/** Remove comments and string literals, so only code remains. */
function strip(src) {
  return src
    .replace(/--\[\[[\s\S]*?\]\]/g, ' ')
    .replace(/--[^\n]*/g, ' ')
    .replace(/\[\[[\s\S]*?\]\]/g, ' "" ')
    .replace(/"(\\.|[^"\\])*"/g, ' "" ')
    .replace(/'(\\.|[^'\\])*'/g, ' "" ');
}

function download(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https.get(url, (res) => {
      if (res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode}`));
        return;
      }
      res.pipe(file);
      file.on('finish', () => file.close(() => resolve(dest)));
    }).on('error', reject);
  });
}

async function loadDb() {
  if (process.argv[2]) return process.argv[2];

  const cached = path.join(os.tmpdir(), 'nifty-native-db.json');
  if (fs.existsSync(cached) && fs.statSync(cached).size > 1_000_000) {
    console.log(`Datenbank aus dem Cache: ${cached}`);
    return cached;
  }

  console.log(`Lade ${DB_URL} ...`);
  await download(DB_URL, cached);
  return cached;
}

(async () => {
  const dbFile = await loadDb();
  const natives = JSON.parse(fs.readFileSync(dbFile, 'utf8'));

  const db = new Set();
  for (const ns of Object.keys(natives)) {
    for (const k of Object.keys(natives[ns])) {
      const e = natives[ns][k];
      if (e && e.name) db.add(e.name);
    }
  }

  const files = [];
  (function walk(dir) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith('.lua')) files.push(p);
    }
  })(ROOT);

  /** Every PascalCase identifier that is CALLED, and where. */
  const calls = new Map();
  for (const f of files) {
    const code = strip(fs.readFileSync(f, 'utf8'));
    const re = /\b(_?[A-Z][A-Za-z0-9]*)\s*\(/g;
    let m;
    while ((m = re.exec(code)) !== null) {
      const name = m[1];
      if (!calls.has(name)) calls.set(name, new Set());
      calls.get(name).add(path.relative(ROOT, f).replace(/\\/g, '/'));
    }
  }

  const unknown = [];
  for (const [name, where] of calls) {
    const snake = toSnake(name);
    if (snake === name) continue;          // SCREAMING_CASE is a constant
    if (db.has(snake)) continue;           // it is documented, so it exists
    unknown.push({ name, snake, files: [...where] });
  }

  console.log(`Aufgerufene PascalCase-Funktionen: ${calls.size}`);
  console.log(`davon nicht in der dokumentierten DB: ${unknown.length}`);
  console.log('');
  for (const u of unknown) {
    console.log(`  ${u.name.padEnd(44)} -> ${u.snake}`);
    for (const f of u.files) console.log(`      ${f}`);
  }
  console.log('');
  console.log('Das ist eine Prüfliste, kein Urteil: CFX-Lua-Builtins und');
  console.log('undokumentierte Game-Natives stehen ebenfalls hier.');

  fs.writeFileSync(
    path.join(os.tmpdir(), 'nifty-native-sweep.json'),
    JSON.stringify(unknown, null, 1),
  );
})();
