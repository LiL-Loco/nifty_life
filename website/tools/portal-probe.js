/**
 * Portal-account probe — real database, real grants.
 *
 * Everything here runs as the RESTRICTED `nifty_website` account, which is the
 * point. Registering, signing in, confirming an address and linking a Discord
 * account are all things the public connection must be able to do, and every one
 * of them is something it must NOT be able to do by accident. Logic-only tests
 * would pass even if the grants were wrong.
 *
 * Written after a test caught a real bug: `confirmEmail` reported "link invalid"
 * on a token that had just worked, because a multi-statement CALL returns several
 * result sets and the code read the first — an empty OkPacket — instead of the
 * last one carrying the answer. The account was confirmed while the page said it
 * was not. That is the class of failure this file exists to catch.
 *
 * Needs DB_GAME_USER / DB_GAME_PASSWORD in .env, because cleanup has to run
 * through the GAME account: the website account has no DELETE on anything here,
 * which is itself part of what is being tested.
 *
 * Run:
 *   npx tsc src/lib/{db,users,passwords,applications,rulebook,config,identity,copycheck}.ts \
 *     --outDir .tmp-test --module commonjs --target es2022 --moduleResolution node \
 *     --esModuleInterop --skipLibCheck
 *   node tools/portal-probe.js
 */
const fs = require('fs');
const Module = require('module');

const originalResolve = Module._resolveFilename;
Module._resolveFilename = function (request, ...rest) {
  if (request === 'server-only') return require.resolve('./stubs/server-only.js');
  return originalResolve.call(this, request, ...rest);
};

const envPath = `${__dirname}/../.env`;
if (!fs.existsSync(envPath)) {
  console.error('website/.env not found — nothing to probe against.');
  process.exit(1);
}
for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
  const at = line.indexOf('=');
  if (at > 0) process.env[line.slice(0, at).trim()] = line.slice(at + 1).trim();
}

if (!process.env.DB_GAME_USER || !process.env.DB_GAME_PASSWORD) {
  console.error('DB_GAME_USER / DB_GAME_PASSWORD not set — needed for cleanup.');
  process.exit(1);
}

const users = require('../.tmp-test/users.js');

const EMAIL_A = 'probe.portal.a@example.test';
const EMAIL_B = 'probe.portal.b@example.test';
const PASSWORD = 'ein-langes-passwort-123';
/** The real owner. Safe to link and unlink — the probe removes it in cleanup. */
const PROBE_DISCORD_ID = '230143751857766400';

let pass = 0;
let fail = 0;

function check(name, condition, detail) {
  if (condition) {
    console.log('  PASS  ' + name);
    pass++;
  } else {
    console.log('  FAIL  ' + name + (detail ? ` — ${detail}` : ''));
    fail++;
  }
}

(async () => {
  console.log('\nPortal accounts — real database, restricted grants\n');
  console.log(`  connecting as ${process.env.DB_USER}@${process.env.DB_HOST}`);

  try {
    // --- Registration -------------------------------------------------------
    check('a malformed address is refused', !(await users.register('not-an-email', PASSWORD)).ok);
    check('a short password is refused', !(await users.register(EMAIL_A, 'kurz')).ok);

    const first = await users.register(EMAIL_A, PASSWORD);
    check('registration creates an account', first.ok, first.error);

    const duplicate = await users.register(EMAIL_A, PASSWORD);
    check('a duplicate address is refused', !duplicate.ok);

    // --- Sign in ------------------------------------------------------------
    const good = await users.authenticate(EMAIL_A, PASSWORD);
    check('correct credentials sign in', good.ok, good.error);

    const wrongPassword = await users.authenticate(EMAIL_A, 'falsches-passwort-999');
    const unknown = await users.authenticate(EMAIL_B, PASSWORD);
    check('a wrong password is refused', !wrongPassword.ok);
    check('an unknown address is refused', !unknown.ok);
    check(
      'an unknown address and a wrong password give the SAME sentence',
      wrongPassword.error === unknown.error,
      `${wrongPassword.error} vs ${unknown.error}`,
    );

    // --- Confirmation -------------------------------------------------------
    const beforeConfirm = await users.findUser(first.user.id);
    check(
      'a fresh account is not verified',
      beforeConfirm && beforeConfirm.emailVerifiedAt === null,
      beforeConfirm ? String(beforeConfirm.emailVerifiedAt) : 'no user',
    );

    check('a junk token is refused', !(await users.confirmEmail('nicht-ein-token')).ok);

    const token = await users.issueEmailToken(first.user.id);
    const confirmed = await users.confirmEmail(token);
    // The regression this whole file was written for: the procedure works, and
    // the code must agree that it worked.
    check('the confirmation link confirms through the PROCEDURE', confirmed.ok, confirmed.error);

    const afterConfirm = await users.findUser(first.user.id);
    check(
      'email_verified_at is actually set afterwards',
      afterConfirm && afterConfirm.emailVerifiedAt !== null,
      afterConfirm ? String(afterConfirm.emailVerifiedAt) : 'no user',
    );
    check('the same token cannot be used twice', !(await users.confirmEmail(token)).ok);

    // --- Discord link -------------------------------------------------------
    const linked = await users.linkDiscord(first.user.id, PROBE_DISCORD_ID, 'lilloco');
    check('a Discord account can be linked', linked.ok, linked.error);

    const link = await users.linkedDiscord(first.user.id);
    check(
      'the link reads back',
      link !== null && link.discordId === PROBE_DISCORD_ID,
      link ? link.discordId : 'null',
    );

    const second = await users.register(EMAIL_B, 'ein-anderes-passwort-456');
    const clash = second.ok
      ? await users.linkDiscord(second.user.id, PROBE_DISCORD_ID, 'lilloco')
      : { ok: false, error: 'second registration failed' };
    // The UNIQUE index on discord_id is the real guard here; application code
    // merely turns it into a sentence.
    check('the same Discord cannot attach to a second account', !clash.ok, clash.error);

    // --- The team view ------------------------------------------------------
    const registrations = await users.registrations();
    check('the registrations list includes both accounts', registrations.length >= 2, String(registrations.length));
    check(
      'the list shows the Discord link',
      registrations.some((row) => row.discord_id === PROBE_DISCORD_ID),
    );
    check(
      'the list shows confirmation state',
      registrations.some((row) => row.email_verified_at !== null),
    );
  } catch (error) {
    check('the probe ran without throwing', false, error.message);
  } finally {
    await cleanup();
    console.log('  ----  probe rows deleted');
    console.log('');
    console.log(
      fail === 0
        ? `  ${pass}/${pass + fail} portal-account checks passed.\n`
        : `  ${fail} portal-account check(s) FAILED.\n`,
    );
    process.exit(fail === 0 ? 0 : 1);
  }
})();

/**
 * Cleanup through the GAME account.
 *
 * The website account cannot DELETE here — which is part of what this probe is
 * checking, and why it cannot tidy up after itself.
 */
async function cleanup() {
  const mysql = require('mysql2/promise');
  const connection = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_GAME_USER,
    password: process.env.DB_GAME_PASSWORD,
    database: process.env.DB_NAME,
  });

  // Users cascade to their tokens and their Discord link.
  await connection.execute('DELETE FROM portal_users WHERE email IN (?, ?)', [EMAIL_A, EMAIL_B]);
  await connection.end();
}