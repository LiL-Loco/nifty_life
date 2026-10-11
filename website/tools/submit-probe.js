/**
 * End-to-end submit probe.
 *
 * Runs the REAL compiled modules against the REAL database as the REAL website
 * account, so it exercises the whole chain in one go:
 *
 *   validateAnswers -> submitApplication -> INSERT as nifty_website -> read back
 *
 * This is the only test that proves the insert is actually permitted by the
 * grant. Everything else is logic.
 *
 * The row it writes is deleted again in `finally`. If the process dies first,
 * one probe row is left behind; it is identifiable by the marker below.
 *
 * Run: node tools/submit-probe.js
 */
const fs = require('fs');
const path = require('path');
const Module = require('module');

// Only `server-only` is stubbed. `./db` is REAL here, and so is mysql2 — the
// point is to talk to the actual database.
const originalResolve = Module._resolveFilename;
Module._resolveFilename = function (request, ...rest) {
  if (request === 'server-only') return require.resolve('./stubs/server-only.js');
  return originalResolve.call(this, request, ...rest);
};

// The compiled code reads process.env, not a .env file — that is Next's job.
const envPath = path.join(__dirname, '..', '.env');
if (!fs.existsSync(envPath)) {
  console.error('website/.env not found — nothing to probe against.');
  process.exit(1);
}
for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
  const at = line.indexOf('=');
  if (at > 0) process.env[line.slice(0, at).trim()] = line.slice(at + 1).trim();
}

const { validateAnswers, submitApplication } = require('../.tmp-test/applications.js');
const { query } = require('../.tmp-test/db.js');
const { RULEBOOK_QUESTIONS } = require('../.tmp-test/rulebook.js');

const PROBE_DISCORD_ID = '999000999000999999';
let probeId = null;
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

function probeForm() {
  const form = new FormData();
  form.set('rulebook_read', 'on');

  // Distinct per question, not "Submit-Probe Antwort N ...". The copy check in
  // `validateAnswers` is real and a fixture of twenty near-identical sentences is
  // exactly what it is meant to reject — the probe was failing on its own filler
  // before it ever reached the database.
  const OPENERS = [
    'Auf dem Server kann man sich mit allen unterhalten und dabei ganz in die Rolle gehen.',
    'Ein Changelog sagt nur etwas ueber den Spielstand und nicht ueber unsere Geschichte.',
    'Ohne Ansage hat das Opfer keine Chance und genau das macht den Unterschied aus.',
    'Ein Motorrad ist lebensgefaehrlich, deshalb muss man dort doppelt vorsichtig sein.',
    'Informationen zu benutzen, die die Figur gar nicht haben kann, ist Meta-Gaming.',
    'Dem Partner etwas vorschreiben, was er nicht mitmacht, ist Power-RP.',
    'Einen Absturz melde ich sofort und warte, bis die Szene sauber weitergeht.',
    'Ich sage freundlich nein und biete an, es beim naechsten Mal anders zu machen.',
    'Wer im Spiel ist, gehoert auch auf den Teamspeak und benimmt sich dort genauso.',
    'Ohne abgesprochenes Einverstaendnis ist es kein genehmigter Antrag, sondern Zwang.',
    'Offene Straenge klare ich vorher mit allen Beteiligten, damit nichts haengenbleibt.',
    'Der Wasted-Timer heisst, dass niemand eingreifen soll, weil die Szene so geplant war.',
    'Nach dem Aufwachen weiss die Figur nichts und darf nicht in die Szene zurueckkehren.',
    'Wer den Fall aufloest, darf die Szene sauber beenden, die Figur selbst bleibt bestehen.',
    'Eine Geiselnahme ist bei Bankraub verboten, weil man sonst keine Ausnahme mehr hat.',
    'Vier pro Seite, und nicht alle vier gleichzeitig bei derselbenillegalen Taetigkeit.',
    'Die Zugehoerigkeit muss sichtbar sein, damit jeder im Bild weiss, wer zu wem gehoert.',
    'Ab dem Moment bin ich raus und der andere hat das Sagen in dieser Szene.',
    'Im OOC darf ich fragen, aber nicht lenken, und nicht absprechen, wie wir es angehen.',
    'Streamen darf ich das Spiel, aber keine Chats und nichts, was der Server nicht zeigen soll.',
  ];

  RULEBOOK_QUESTIONS.forEach((question, index) => {
    form.set(`answer_${question.id}`, OPENERS[index % OPENERS.length] + ` (${index + 1})`);
  });
  return form;
}

(async () => {
  console.log('\nSubmit probe — real modules, real database, real grants\n');
  console.log(`  connecting as ${process.env.DB_USER}@${process.env.DB_HOST}`);

  try {
    const answers = validateAnswers(probeForm());
    check('validation passes before anything is written', typeof answers === 'object');

    const result = await submitApplication(PROBE_DISCORD_ID, answers);
    check('the insert is permitted by the grant', result.ok, result.error);
    if (!result.ok) return finish();

    probeId = result.id;

    const rows = await query('SELECT id, discord_id, status, answers FROM applications WHERE id = ?', [probeId]);
    check('the row is readable back', rows.length === 1);

    // mysql2 parses JSON columns into objects on the way out, so the value may
    // already be parsed depending on driver path. Accept both rather than
    // asserting one shape the database does not actually promise.
    const raw = rows[0] ? rows[0].answers : null;
    const stored = typeof raw === 'string' ? JSON.parse(raw) : raw;
    check('the stored answers carry the rulebook acknowledgement',
      stored.rulebook && stored.rulebook.read === true);
    check('all twenty answers were stored',
      stored.answers && stored.answers.length === 20,
      'got ' + (stored.answers && stored.answers.length));
    check('the answers were stored in rulebook order',
      stored.answers && stored.answers.every((a, i) => a.id === RULEBOOK_QUESTIONS[i].id));
    check('each answer was stored together with its question',
      stored.answers && stored.answers.every((a) => typeof a.question === 'string' && a.question.length > 10));
    check('the server stamped the acknowledgement time',
      stored.rulebook && !Number.isNaN(Date.parse(stored.rulebook.at)));
    check('the acknowledgement carries a rulebook version',
      stored.rulebook && typeof stored.rulebook.version === 'string');
    check('it lands as "submitted", not approved',
      rows[0] && rows[0].status === 'submitted');

    // ---- One application per person, ever (migration 010) ------------------
    // The rule is a UNIQUE index. The pre-check inside submitApplication is only
    // a courtesy that produces a readable message, so the thing worth proving is
    // the raw constraint: a second row for the same Discord ID must be refused by
    // the database even when nothing in the application layer is consulted.
    let secondInsert = 'allowed';
    try {
      await query(
        'INSERT INTO applications (id, discord_id, answers) VALUES (?, ?, ?)',
        [newProbeUuid(), PROBE_DISCORD_ID, JSON.stringify({ probe: true })],
      );
    } catch (error) {
      secondInsert = error.errno === 1062 ? 'refused' : `error:${error.code}`;
    }
    check('the unique index refuses a second application for the same person',
      secondInsert === 'refused', 'got ' + secondInsert);

    // And the application-level refusal is readable, not a driver message.
    const second = await submitApplication(PROBE_DISCORD_ID, answers);
    check('a second submit through the app is refused with a sentence',
      !second.ok && second.error.includes('bereits'),
      'got ' + JSON.stringify(second));

    // The whole point of ADR-0007, exercised rather than asserted.
    let couldApprove = false;
    try {
      await query("UPDATE applications SET status='approved' WHERE id = ?", [probeId]);
      couldApprove = true;
    } catch {
      couldApprove = false;
    }
    check('the website still cannot approve its own application', !couldApprove);
  } catch (error) {
    check('the probe ran without throwing', false, error.message);
  } finally {
    if (probeId) {
      try {
        // The website account cannot DELETE, which is the boundary working. The
        // cleanup therefore has to be an admin connection.
        await cleanup(probeId);
        console.log('  ----  probe row deleted');
      } catch (error) {
        console.log('  ----  probe row ' + probeId + ' left behind: ' + error.message);
      }
    }
    finish();
  }
})();

function newProbeUuid() {
  return require('crypto').randomUUID();
}

/**
 * Cleanup through the GAME account, which has full privileges on the schema.
 *
 * Not through `root`: the local root uses an auth plugin this driver does not
 * negotiate, and adding a second privileged credential to a test harness for the
 * sake of one DELETE is a poor trade.
 */
async function cleanup(id) {
  const mysql = require('mysql2/promise');
  const conn = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_GAME_USER,
    password: process.env.DB_GAME_PASSWORD,
    database: process.env.DB_NAME,
  });
  await conn.execute('DELETE FROM applications WHERE id = ?', [id]);
  await conn.end();
}

function finish() {
  console.log('');
  if (fail === 0) {
    console.log(`  ${pass}/${pass + fail} probe checks passed.\n`);
    process.exit(0);
  } else {
    console.log(`  ${fail} probe check(s) FAILED.\n`);
    process.exit(1);
  }
}