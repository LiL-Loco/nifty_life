#!/usr/bin/env node
/**
 * nui-export-sweep — which NUI callbacks have no working export behind them?
 *
 * WHY THIS EXISTS
 *
 * A NUI panel calls its Lua side through a callback. The callback resolves the
 * export through a wrapper table, and the wrapper is a LINE OF CODE that
 * somebody has to remember to write. When it is missing, the panel gets
 * nothing, the panel shows a fallback, and the only trace is one line in the
 * CLIENT console:
 *
 *     [cl_nui] tried to call missing export "getItemNames"
 *
 * Which is a line nobody reads, for a button that does nothing.
 *
 * The two ways this goes wrong, and both are checked here:
 *
 *   1. a callback names a wrapper the api table does not have
 *      -> the callback always fails
 *   2. a callback names an export that does not exist, in this resource or
 *      in another one
 *      -> the callback always fails
 *
 * A callback that does its work itself - a local function, a server event -
 * is fine and is not reported.
 *
 * HOW TO RUN
 *
 *   node tools/nui-export-sweep.js
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', 'resources', '[nifty]');

/** Every .lua file of a resource, by client / server / shared. */
function luaFiles(resourceDir) {
  const out = { client: [], server: [], shared: [] };
  for (const kind of ['client', 'server', 'shared']) {
    const dir = path.join(resourceDir, kind);
    if (!fs.existsSync(dir)) continue;
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.isFile() && e.name.endsWith('.lua')) out[kind].push(path.join(dir, e.name));
    }
  }
  return out;
}

const read = (f) => fs.readFileSync(f, 'utf8');
const rel = (f) => path.relative(ROOT, f).replace(/\\/g, '/');

/** The names in a `local api = { ... }` wrapper table. */
function apiKeys(src) {
  const start = src.indexOf('local api = {');
  if (start < 0) return [];
  const end = src.indexOf('\n}', start);
  if (end < 0) return [];
  const body = src.slice(start, end);
  const keys = [];
  for (const m of body.matchAll(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function/gm)) {
    keys.push(m[1]);
  }
  return keys;
}

const resources = fs.readdirSync(ROOT, { withFileTypes: true })
  .filter((e) => e.isDirectory())
  .map((e) => e.name);

/**
 * Every resource's CLIENT exports, by resource name.
 *
 * Collected first, because a callback may reach into ANOTHER resource, and
 * "does that export exist there" can only be answered once every resource has
 * been read.
 */
const otherExports = new Map();
for (const name of resources) {
  const files = luaFiles(path.join(ROOT, name));
  const set = new Set();
  for (const f of files.client) {
    for (const m of read(f).matchAll(/exports\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]/g)) {
      set.add(m[1]);
    }
  }
  otherExports.set(name, set);
}

let problems = 0;
let checked = 0;

for (const name of resources) {
  const dir = path.join(ROOT, name);
  const files = luaFiles(dir);
  if (!files.client.length) continue;

  const clientSrc = files.client.map((f) => ({ file: rel(f), src: read(f) }));

  // The exports the resource offers on the CLIENT.
  const clientExports = new Map();
  for (const { file, src } of clientSrc) {
    for (const m of src.matchAll(/exports\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]/g)) {
      if (!clientExports.has(m[1])) clientExports.set(m[1], file);
    }
  }

  // The NUI callbacks and the wrapper table.
  for (const { file, src } of clientSrc) {
    if (!/RegisterNUICallback/.test(src)) continue;

    const callbacks = [...src.matchAll(/RegisterNUICallback\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]/g)]
      .map((m) => m[1]);
    if (!callbacks.length) continue;

    const keys = new Set(apiKeys(src));
    checked += callbacks.length;

    // The body of a callback, so it can be asked what it actually calls.
    // It ends where the NEXT callback begins - otherwise a callback is
    // credited with the calls of its successor.
    const bodyOf = (cb) => {
      const at = src.indexOf(`RegisterNUICallback('${cb}'`);
      if (at < 0) return '';
      const next = src.indexOf('RegisterNUICallback(', at + 10);
      return src.slice(at, next < 0 ? src.length : next);
    };

    for (const cb of callbacks) {
      const body = bodyOf(cb);

      // A callback can be served in many ways: through the wrapper table, by
      // calling an export of its own resource, by calling the export of
      // another resource, or by doing the work itself with a local function
      // or a server event. All of those are legitimate.
      //
      // What is NOT legitimate is naming something that does not exist, and
      // that is the only thing worth reporting: the callback asks for an
      // export that was never written, and the panel gets nothing.
      const viaWrapper = /tryCall\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]/.exec(body);
      if (viaWrapper && !keys.has(viaWrapper[1])) {
        problems += 1;
        console.log(`  FEHLT  ${name}: Callback "${cb}" ruft tryCall('${viaWrapper[1]}'), aber die api-Tabelle kennt "${viaWrapper[1]}" nicht`);
        continue;
      }

      // exports[RESOURCE]:name(...)  - the resource's own client export.
      const own = /exports\[RESOURCE\]\s*:\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(/.exec(body);
      if (own && !clientExports.has(own[1])) {
        problems += 1;
        console.log(`  FEHLT  ${name}: Callback "${cb}" ruft den Export "${own[1]}", den es nicht gibt`);
        continue;
      }

      // exports['other-resource']:name(...)  - somebody else's export.
      for (const m of body.matchAll(/exports\[\s*['"]([A-Za-z0-9_\-]+)['"]\s*:\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(/g)) {
        const [, target, exportName] = m;
        if (target === 'RESOURCE') continue;
        if (!otherExports.has(target)) {
          problems += 1;
          console.log(`  FEHLT  ${name}: Callback "${cb}" ruft den Export "${exportName}" von "${target}" - die Ressource kennt kein Client-Export "${exportName}"`);
          continue;
        }
        if (!otherExports.get(target).has(exportName)) {
          problems += 1;
          console.log(`  FEHLT  ${name}: Callback "${cb}" ruft "${target}:${exportName}" - diesen Export gibt es dort nicht`);
        }
      }
    }

    for (const key of keys) {
      if (!clientExports.has(key)) {
        problems += 1;
        console.log(`  FEHLT  ${name}: Wrapper "${key}" zeigt auf einen Export, den es nicht gibt`);
      }
    }
  }
}

console.log('');
console.log(`geprüfte Callbacks: ${checked}, Probleme: ${problems}`);
if (problems === 0) console.log('alles verdrahtet');
