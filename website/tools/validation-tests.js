/**
 * Server-side validation harness.
 *
 * The step wizard checks the answers in the browser as a convenience, but that
 * check is worthless as a guarantee — the client controls the FormData entirely.
 * `validateAnswers` is the real gate, so this runs the REAL compiled module.
 *
 * It exists because "the form made it impossible" is not the same claim as "the
 * server refuses it", and only the second one protects the review queue.
 *
 * Run:
 *   npx tsc src/lib/{applications,rulebook,config,identity,copycheck,db,session}.ts \
 *     --outDir .tmp-test --module commonjs --target es2022 --moduleResolution node \
 *     --esModuleInterop --skipLibCheck
 *   node tools/validation-tests.js
 */
const path = require('path');
const Module = require('module');

// `server-only` exists to make a mistake fail loudly inside a React Server
// Component tree. Under plain Node there is no such tree, so it is stubbed here
// rather than removed from the source.
//
// `./db` is stubbed for the same reason: `validateAnswers` is pure string work
// that never touches a connection. Letting it pull in mysql2 and then demand
// real DB credentials would make a validation test fail for reasons that have
// nothing to do with validation.
const originalResolve = Module._resolveFilename;
Module._resolveFilename = function (request, ...rest) {
  if (request === 'server-only') return require.resolve('./stubs/server-only.js');
  if (request === './db') return require.resolve('./stubs/db.js');
  return originalResolve.call(this, request, ...rest);
};

// `config.ts` refuses to load without database credentials, and the session
// module needs it for SESSION_SECRET. These are throwaway values: nothing below
// opens a connection, and `decodeSession` only compares HMACs.
process.env.DB_HOST ||= '127.0.0.1';
process.env.DB_USER ||= 'probe';
process.env.DB_PASSWORD ||= 'probe';
process.env.DB_NAME ||= 'probe';
process.env.SESSION_SECRET ||= 'probe-secret-not-used-for-anything-real';

const { validateAnswers } = require('../.tmp-test/applications.js');
const { RULEBOOK_QUESTIONS } = require('../.tmp-test/rulebook.js');
const { checkForCopying, copyWarningMessage } = require('../.tmp-test/copycheck.js');
const { encodeSession, decodeSession } = require('../.tmp-test/session.js');
const { createHmac } = require('crypto');

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

const ANSWER_MIN = 25;
const ANSWER_MAX = 2000;

/**
 * Twenty realistic answers, one per question.
 *
 * These exist because the copy detector works on word sequences, and any
 * TEMPLATED filler is by construction twenty near-identical sentences. The first
 * version of this file generated "Antwort N auf §N ...", and once the
 * cross-answer threshold was set from measured data the suite went red on 34
 * checks — correctly: that filler really is twenty answers differing only by a
 * number, which is exactly the abuse the detector exists to catch.
 *
 * So the fixture has to be honest. Their worst pairwise similarity is 0.000.
 */
const ANSWERS = [
  'IC ist die Haltung im Spiel und OOC der Raum daneben. Alles was ich dort mitkriege, kann ich hier nicht einfach benutzen, weil mein Charakter davon nichts wissen darf und die Geschichte sonst aufgebraucht ist.',
  'Nein. Ein Changelog ist eine Information an alle Spieler ueber den Spielstand, nicht ueber die Geschehnisse unserer Geschichte. Wenn ich das im IC wusste, wuerde ich Figuren verhalten, die es noch gar nicht gibt.',
  'RDM heisst, dass der Ausloeser beliebig ist und das Opfer keine Zeit hat zu reagieren. VDM ist die gleiche Situation, aber mit Ansage. Der Unterschied ist die Fairness fuer die beteiligte Person, nicht die Schwere.',
  'Weil ein Fahrzeug in der Realitaet kein gezieltes Werkzeug gegen eine Person ist, sondern im Zweifel jeder benutzen kann. Beim Motorrad besonders aufpassen, weil ein Fehler direkt lebensgefaehrlich endet und man da nicht zurueckkommen kann.',
  'Meta-Gaming heisst, Informationen zu benutzen, die der Charakter nicht haben kann, zum Beispiel durch Zuschauen oder Ueberlisten von Handelswegen. Das faellt unter einen dauerhaften Bann, deshalb muss man vooraus denken statt zurueck zu schlagen.',
  'Power-RP heisst, dem Partner Vorgaben zu machen, die er nicht mitformt, zum Beispiel ungefragt zu entscheiden, was er tut. Ein lautes Ueberfall wirkt vielleicht nach Aktion, aber das Gegenueber hat keine Szene und damit auch keine Antwort darauf.',
  'Ich schreibe sofort in den Discord, was passiert ist, und warte, bis es weitergeht. In einer laufenden Szene heisst das nicht, einfach weiterzuspielen oder das untereinander wegzureden, sondern es sauber abzubrechen.',
  'Ich sage freundlich und deutlich, dass ich darauf nicht eingehe, und biete an, das naechste Mal anders zu machen. Niemanden zu beschimpfen oder einen Vorwurf zu machen, der dann im Chat landet und die Stimmung kippt.',
  'Wenn ich im Spiel bin, bin ich auch auf dem TS und hoere zu, damit ich nicht aus dem Team rausfliege. Das Mikro bleibt offen, aber ruhig und ohne Fluchen, weil man auch da als derselbe Mensch auftritt wie im RP.',
  'Ein genehmigter Antrag ist abgesprochen, es gibt Zustimmung und das Ganze laeuft vorher wie ein Gespraech. Ein aufgezwungenes RP nimmt jemandem die Entscheidung weg und ist damit genau das, was das Regelwerk verbietet.',
  'Vorher schliesse ich laufende Sachen ab, damit nichts mitten im Bild haengenbleibt, und klaere die offenen Straenge mit den Beteiligten. Danach reisen die betroffenen Figuren weiter, weil die Woche nicht fuer sie stillsteht.',
  'Der Timer sagt, dass niemand mehr aus eigenem Antrieb eingreifen darf, weil die Szene laeuft und nicht gerettet werden soll. Ohne Mediziner bleibt man liegen und redet erst, wenn jemand kommt oder es sich aufloest.',
  'Weil ich dann zurueck in eine Szene kaeme, von der ich nichts weiss, und daraus wuerde sofort eine Katastrophe. Was ich bewusstlos mitbekommen habe, darf ich hinterher nicht verwenden, weil mein Charakter es nicht erlebt hat.',
  'Wer den Fall aufloest oder die Situation ordentlich beendet, und danach geht es dort weiter, so als waere nichts gewesen. Ein Moment ist damit beendet, nicht die Existenz der Figur.',
  'Bei einem Bankraub und wenn jemand als Geisel genommen werden soll, weil da kein Weg raus ist. Und ausserdem in Gebaeuden mit Publikumsverkehr, da mischt man Unbeteiligte mit hinein.',
  'Vier Personen pro Seite, und an einer illegalen Taetigkeit duerfen nicht alle vier gleichzeitig mitmachen. Sonst waere eine Gruppe ploetzlich stark genug fuer alles, was das Regelwerk verbietet.',
  'Die Zugehoerigkeit muss sichtbar sein, damit jeder im Bild weiss, wer zu wem gehoert. Und es endet, sobald der Grund wegfaellt oder eine Seite kapituliert, nicht einfach weil die Uhr abgelaufen ist.',
  'Ab dem Moment bin ich fuer die Szene raus und der andere hat das Sagen. Was vorher besprochen war, kann ich einfordern, aber ich renne nicht weg und baue keine Szene, die er gerade abhaengt.',
  'Erlaubt ist er bei Fragen zur laufenden Szene oder wenn etwas technisch klemmt. Nicht erlaubt ist er, um eine laufende Situation zu lenken oder sich abzusprechen, wie man sie angeht.',
  'Streamen darf ich das Spiel, aber keine Chats und keine Personen ohne deren Einverstaendnis. Ausserdem muss ich die Ausschlusszeiten einhalten und darf nichts zeigen, was der Server nicht zeigen soll.',
];

/**
 * A complete, honest application: every question answered in its own words, plus
 * the rulebook confirmation.
 */
function completeForm(overrides = {}) {
  const form = new FormData();
  form.set('rulebook_read', 'on');

  RULEBOOK_QUESTIONS.forEach((question, index) => {
    form.set(`answer_${question.id}`, ANSWERS[index]);
  });

  for (const [key, value] of Object.entries(overrides)) {
    if (value === null) form.delete(key);
    else form.set(key, value);
  }
  return form;
}

console.log('\nServer-side validation — the gate the wizard is not\n');

// --- The shape of the rulebook itself ---------------------------------------
check('the rulebook asks exactly twenty questions', RULEBOOK_QUESTIONS.length === 20,
  'got ' + RULEBOOK_QUESTIONS.length);
check('question ids are unique',
  new Set(RULEBOOK_QUESTIONS.map((q) => q.id)).size === RULEBOOK_QUESTIONS.length);
check('every question carries a section reference',
  RULEBOOK_QUESTIONS.every((q) => typeof q.ref === 'string' && q.ref.length > 0));
check('every question asks something', RULEBOOK_QUESTIONS.every((q) => q.question.length > 10));

// --- The happy path ---------------------------------------------------------
const good = validateAnswers(completeForm());
check('a complete application is accepted', typeof good === 'object', 'got ' + JSON.stringify(good));
check('all twenty answers are stored',
  typeof good === 'object' && good.answers.length === 20,
  'got ' + (good && good.answers && good.answers.length));
check('the answers come back in rulebook order',
  typeof good === 'object' && good.answers.every((a, i) => a.id === RULEBOOK_QUESTIONS[i].id));
check('the reading is recorded as a fact',
  typeof good === 'object' && good.rulebook.read === true);
check('the server stamps the timestamp, not the client',
  typeof good === 'object' && !Number.isNaN(Date.parse(good.rulebook.at)));
check('the acknowledgement carries a rulebook version',
  typeof good === 'object' && typeof good.rulebook.version === 'string' && good.rulebook.version.length > 0);

// --- The question snapshot --------------------------------------------------
check('the question is stored WITH the answer',
  typeof good === 'object' && good.answers[0].question.includes(RULEBOOK_QUESTIONS[0].question));
check('the stored question carries its section reference',
  typeof good === 'object' && good.answers[0].question.startsWith(RULEBOOK_QUESTIONS[0].ref));

// --- The rulebook gate ------------------------------------------------------
check('no "read it" confirmation is refused',
  typeof validateAnswers(completeForm({ rulebook_read: null })) === 'string');
check('a wrong value instead of the confirmation is refused',
  typeof validateAnswers(completeForm({ rulebook_read: 'yes' })) === 'string');

// --- Every question is required, every one of them --------------------------
for (const question of RULEBOOK_QUESTIONS) {
  const missing = validateAnswers(completeForm({ [`answer_${question.id}`]: null }));
  check(`a missing answer to ${question.id} is refused`, typeof missing === 'string');

  const empty = validateAnswers(completeForm({ [`answer_${question.id}`]: '   ' }));
  check(`a whitespace-only answer to ${question.id} is refused`, typeof empty === 'string');

  const tooShort = validateAnswers(completeForm({ [`answer_${question.id}`]: 'nein' }));
  check(`a one-word answer to ${question.id} is refused`, typeof tooShort === 'string');

  const justLongEnough = validateAnswers(
    completeForm({ [`answer_${question.id}`]: 'a'.repeat(ANSWER_MIN) }),
  );
  check(`an answer of exactly the minimum length passes ${question.id}`,
    typeof justLongEnough === 'object');
}

// --- Size and content limits ------------------------------------------------
check('an oversized answer is refused',
  typeof validateAnswers(completeForm({ answer_q01: 'x'.repeat(ANSWER_MAX + 1) })) === 'string');
check('an answer of exactly the maximum length passes',
  typeof validateAnswers(completeForm({ answer_q01: 'x'.repeat(ANSWER_MAX) })) === 'object');

// Control characters, written as escapes so this file has no raw NUL in it.
check('control characters in an answer are refused',
  typeof validateAnswers(completeForm({ answer_q01: 'ab' })) === 'string');
check('a newline inside an answer is refused',
  typeof validateAnswers(completeForm({ answer_q01: 'a\nb' })) === 'string');
check('a NUL inside an answer is refused',
  typeof validateAnswers(completeForm({ answer_q01: 'a b' })) === 'string');

// --- The removed fields are gone -------------------------------------------
for (const ghost of ['age', 'timezone', 'experience', 'motivation']) {
  const form = completeForm();
  form.set(ghost, 'irrelevant');
  check(`a "${ghost}" field is ignored, not required`,
    typeof validateAnswers(form) === 'object');
}
const boxOnly = new FormData();
boxOnly.set('rulebook_read', 'on');
check('the application cannot be faked with only the rulebook box',
  typeof validateAnswers(boxOnly) === 'string');

// --- Every answer is required at SUBMIT time --------------------------------
// Navigation in the wizard lets an empty box be stepped over; the form as a whole
// may not be submitted until all twenty are there. "Frage 3, Frage 7" names them
// rather than only refusing, because the alternative is being told twenty times.
for (const question of RULEBOOK_QUESTIONS) {
  const result = validateAnswers(completeForm({ [`answer_${question.id}`]: null }));
  const position = RULEBOOK_QUESTIONS.findIndex((q) => q.id === question.id) + 1;
  check(`a missing answer to ${question.id} names the position`,
    typeof result === 'string' && result.includes(String(position)),
    'got ' + JSON.stringify(result));
}

const twoMissing = validateAnswers(
  completeForm({ answer_q02: null, answer_q07: null }),
);
check('several missing answers are reported together',
  typeof twoMissing === 'string' && twoMissing.includes('2') && twoMissing.includes('7'),
  'got ' + JSON.stringify(twoMissing));

// --- Copied answers ---------------------------------------------------------
// The FALSE-POSITIVE side comes first, with realistic text rather than filler.
// Synthetic answers ("Antwort 3 auf §3 ...") prove nothing: they share no word
// sequences with each other and never came close to a threshold. These ten were
// written the way a careful applicant would, and several are deliberately on the
// same theme, because that is where a false positive would actually appear.
// Their worst pairwise similarity is 0.000 — and they must stay that way.
// All twenty realistic answers must survive the copy check untouched.
check('twenty realistic honest answers are not flagged',
  checkForCopying({
    answers: ANSWERS.map((answer, i) => ({
      id: RULEBOOK_QUESTIONS[i].id,
      question: RULEBOOK_QUESTIONS[i].question,
      answer,
    })),
  }).suspicious === false);
// The same sentence written to every question.
const repeated = new FormData();
repeated.set('rulebook_read', 'on');
for (const question of RULEBOOK_QUESTIONS) {
  repeated.set(
    `answer_${question.id}`,
    'Weil man als Spieler auf den Server gehen kann und eine Wohnung findet.',
  );
}
const repeatedResult = validateAnswers(repeated);
check('the same answer written twenty times is held back', typeof repeatedResult === 'string');
check('the repeat warning asks for own words',
  typeof repeatedResult === 'string' && /eigenen Worten/i.test(repeatedResult),
  'got ' + JSON.stringify(repeatedResult));

// ...and the applicant can confirm and go through anyway. A moderator reads the
// answers and decides; the form does not make that call for them.
repeated.set('own_words_ack', 'on');
check('confirming stands behind the answers lets them through',
  typeof validateAnswers(repeated) === 'object');

// NEAR-duplicates, not exact ones. An earlier version of this check used one
// identical sentence, which passes even with the similarity threshold set to
// 0.99 — i.e. it proved exact matching and said nothing about the threshold.
// Counter-testing it (raise crossAnswerSimilarity, expect red) is what turned
// this from decoration into a real assertion.
//
// Every answer must be DISTINCT here, and they must differ only in a detail.
// The first attempt reused five sentences four times each, which left every
// answer with an exact twin: the group formed at any threshold, so raising the
// threshold changed nothing and the counter-test stayed green — the test was
// passing for a reason unrelated to what it claimed to check.
const nearDuplicate = new FormData();
nearDuplicate.set('rulebook_read', 'on');
RULEBOOK_QUESTIONS.forEach((question, index) => {
  nearDuplicate.set(
    `answer_${question.id}`,
    'Auf dem Server kann man sich mit allen unterhalten und dabei austauschen, ' +
      `das war bei mir Punkt ${index + 1} auf der Liste und hat so funktioniert.`,
  );
});
check('near-identical but distinct answers are held back',
  typeof validateAnswers(nearDuplicate) === 'string');

nearDuplicate.set('own_words_ack', 'on');
check('near-identical answers pass once confirmed',
  typeof validateAnswers(nearDuplicate) === 'object');

// An answer that only restates its own question.
const echo = completeForm();
echo.set(
  'answer_q01',
  'IC und OOC, und man darf Wissen aus dem OOC nicht im IC verwenden, genau darum.',
);
check('an answer that restates its own question is held back',
  typeof validateAnswers(echo) === 'string');
echo.set('own_words_ack', 'on');
check('a self-reference passes once confirmed', typeof validateAnswers(echo) === 'object');

// --- The rulebook-text check, on and off -----------------------------------
const lifted = [
  { id: 'q01', question: 'A', answer: 'Vereinbart wird hier nicht uebertragen und das gilt.' },
];
const withoutText = checkForCopying({
  answers: lifted,
  rulebookReferenceText: '',
});
check('without rulebook text the check says so',
  withoutText.rulebookTextAvailable === false);
check('the warning does not claim the rulebook was checked',
  /nicht|lediglich/i.test(copyWarningMessage(withoutText, ['q01'])),
  'got ' + copyWarningMessage(withoutText, ['q01']));

const withText = checkForCopying({
  answers: lifted,
  rulebookReferenceText:
    'Vereinbart wird hier nicht uebertragen. Was im OOC besprochen wurde, bleibt dort.',
});
check('with rulebook text a lifted sentence is caught',
  withText.suspicious === true && withText.rulebookTextAvailable === true);
check('a sentence that is NOT in the reference passes',
  checkForCopying({
    answers: [{ id: 'q1', question: 'A', answer: 'Ich finde das unfair, weil es niemandem hilft.' }],
    rulebookReferenceText: 'Vereinbart wird hier nicht uebertragen.',
  }).suspicious === false);

// --- The session cookie ----------------------------------------------------
// The session moved from a Discord ID to a portal user UUID, and the failure
// this guards against is specific and quiet: a cookie minted by the PREVIOUS
// build still verifies its HMAC perfectly well, so without an explicit shape
// check it decodes into an object with `userId: undefined`, every `findUser`
// call stringifies that into "WHERE id = undefined", and the site answers
// "signed in" to everybody holding a stale cookie while doing nothing useful.
const GOOD_UUID = '3f9b1c2e-4a5d-4e6f-8a7b-1c2d3e4f5061';
const cookie = encodeSession({ userId: GOOD_UUID, email: 'probe@example.test' });

const decoded = decodeSession(cookie);
check('a fresh cookie round-trips', decoded !== null && decoded.userId === GOOD_UUID);
check('a fresh cookie keeps the email', decoded !== null && decoded.email === 'probe@example.test');
check('a missing cookie is not a session', decodeSession(undefined) === null);
check('an empty cookie is not a session', decodeSession('') === null);
check('a cookie without a signature is not a session', decodeSession('abc.def') === null);

// The old format, re-signed with the CURRENT secret so the signature is valid.
// This is the exact shape a signed-in visitor had yesterday.
//
// It is refused by BOTH shape checks — it has no `userId` AND no `email` — so
// this assertion on its own cannot tell you the `userId` check works. That is
// what the counter-test showed: deleting the UUID check left this test green and
// turned only the non-UUID case red. The two are kept together for that reason:
// this one proves the real-world upgrade path is closed, the one below isolates
// the `userId` half.
const legacyPayload = Buffer.from(
  JSON.stringify({
    discordId: '230143751857766400',
    username: 'lilloco',
    avatar: null,
    expiresAt: Date.now() + 60_000,
  }),
).toString('base64url');
const legacySignature = createHmac('sha256', process.env.SESSION_SECRET)
  .update(legacyPayload)
  .digest('base64url');
check(
  'a correctly-signed cookie from the OLD format is refused',
  decodeSession(`${legacyPayload}.${legacySignature}`) === null,
);

check('a cookie with a non-UUID user id is refused',
  decodeSession(encodeSession({ userId: 'not-a-uuid', email: 'probe@example.test' })) === null);
check('a cookie whose signature was tampered with is refused',
  decodeSession(cookie.slice(0, -2) + 'xy') === null);

// `encodeSession` always stamps a future expiry, so an expired cookie has to be
// built by hand — with a valid signature, which is the point: expiry is a claim
// inside the payload, not something the signature covers differently.
const expiredPayload = Buffer.from(
  JSON.stringify({ userId: GOOD_UUID, email: 'probe@example.test', expiresAt: 1 }),
).toString('base64url');
const expiredSignature = createHmac('sha256', process.env.SESSION_SECRET)
  .update(expiredPayload)
  .digest('base64url');
check(
  'an expired cookie is refused',
  decodeSession(`${expiredPayload}.${expiredSignature}`) === null,
);

console.log('');
if (fail === 0) {
  console.log(`  ${pass}/${pass + fail} validation checks passed.\n`);
  process.exit(0);
} else {
  console.log(`  ${fail} validation check(s) FAILED.\n`);
  process.exit(1);
}