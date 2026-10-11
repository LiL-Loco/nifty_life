/**
 * Staff-gate probe.
 *
 * Proves the whole chain behind `isStaff()`:
 *
 *   Discord role  ->  bot writes the row (simulated here with the GAME account)
 *                 ->  website reads it with the RESTRICTED website account
 *                 ->  requireStaff() resolves
 *
 * The middle step is the one that matters. It used to run through `web_links` and
 * `characters.is_staff`, which meant the admin area could not be reached until a
 * client had connected — and no client ever has, so the approval path would have
 * shipped untested. Now the mirror is keyed on the Discord ID alone, and this
 * probe demonstrates that a Discord ID with no character and no account row can
 * open /admin.
 *
 * The row is deleted again in `finally`. If the process dies first, one row is
 * left behind holding PROBE_DISCORD_ID, which no real account can claim.
 *
 * Run: see validation-tests.js for the compile step, then inject DB_GAME_USER and
 * DB_GAME_PASSWORD into .env and run:
 *   node tools/staff-probe.js
 */
const fs = require('fs');
const path = require('path');
const Module = require('module');

const originalResolve = Module._resolveFilename;
Module._resolveFilename = function (request, ...rest) {
  if (request === 'server-only') return require.resolve('./stubs/server-only.js');
  return originalResolve.call(this, request, ...rest);
};

const envPath = path.join(__dirname, '..', '.env');
if (!fs.existsSync(envPath)) {
  console.error('website/.env not found — nothing to probe against.');
  process.exit(1);
}
for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
  const at = line.indexOf('=');
  if (at > 0) process.env[line.slice(0, at).trim()] = line.slice(at + 1).trim();
}

if (!process.env.DB_GAME_USER || !process.env.DB_GAME_PASSWORD) {
  console.error('DB_GAME_USER / DB_GAME_PASSWORD not set — the bot account is needed to write.');
  process.exit(1);
}

const { isStaff } = require('../.tmp-test/identity.js');

/** No account row, no character, no web_links entry. This is the point. */
const PROBE_DISCORD_ID = '999000999000999999';
const PROBE_ROLE_ID = '999000999000999998';

let pass = 0;
let fail = 0;

function check(name, condition, detail) {
  if (condition) {
    console.log('  PASS  ' + name);
    pass++;
  } else {
    console.log('  FAIL  ' + name + (detail ? ' — ' + detail : ''));
    fail++;
  }
}

let gameConnection = null;

async function withGameAccount(fn) {
  const mysql = require('mysql2/promise');
  gameConnection = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_GAME_USER,
    password: process.env.DB_GAME_PASSWORD,
    database: process.env.DB_NAME,
  });
  return fn(gameConnection);
}

(async () => {
  console.log('\nStaff gate — bot writes, restricted website account reads\n');

  try {
    // Before: nobody is staff.
    check('an unknown Discord ID is not staff', (await isStaff(PROBE_DISCORD_ID)) === false);

    await withGameAccount(async (connection) => {
      // Exactly what the bot does on guildMemberUpdate.
      await connection.execute(
        `INSERT INTO staff (discord_id, role_id) VALUES (?, ?)
           ON DUPLICATE KEY UPDATE role_id = VALUES(role_id), synced_at = NOW()`,
        [PROBE_DISCORD_ID, PROBE_ROLE_ID],
      );
    });

    // The website account only has SELECT here. This is the real assertion.
    check('a mirrored Discord ID is staff without any character', (await isStaff(PROBE_DISCORD_ID)) === true);

    // Removing the role must remove access — a flag somebody has to remember to
    // clear would keep a removed moderator in the admin area for ever.
    await withGameAccount(async (connection) => {
      await connection.execute('DELETE FROM staff WHERE discord_id = ?', [PROBE_DISCORD_ID]);
    });

    check('losing the role revokes access', (await isStaff(PROBE_DISCORD_ID)) === false);

    // A malformed ID must never reach the query.
    check('a non-numeric Discord ID is refused', (await isStaff('not-an-id')) === false);
    check('an empty Discord ID is refused', (await isStaff('')) === false);
  } catch (error) {
    check('the probe ran without throwing', false, error.message);
  } finally {
    if (gameConnection) {
      try {
        await gameConnection.execute('DELETE FROM staff WHERE discord_id = ?', [PROBE_DISCORD_ID]);
        console.log('  ----  probe row deleted');
      } catch (error) {
        console.log('  ----  probe row ' + PROBE_DISCORD_ID + ' left behind: ' + error.message);
      }
      await gameConnection.end();
    }

    console.log('');
    if (fail === 0) {
      console.log(`  ${pass}/${pass + fail} staff-gate checks passed.\n`);
      process.exit(0);
    } else {
      console.log(`  ${fail} staff-gate check(s) FAILED.\n`);
      process.exit(1);
    }
  }
})();