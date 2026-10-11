// Stub for `./db` — see tools/validation-tests.js.
//
// `validateAnswers` performs no I/O. These exist only so the module resolves;
// every one of them throws if anything ever calls it, which is the point: a
// silent no-op stub would let a test pass against code that was never reached.
function unreachable(name) {
  throw new Error(`validation-tests stub called: ${name} — validateAnswers must not touch the database`);
}

module.exports = {
  query: () => unreachable('query'),
  one: () => unreachable('one'),
  insert: () => unreachable('insert'),
  transaction: () => unreachable('transaction'),
  db: () => unreachable('db'),
  newUuid: () => '00000000-0000-4000-8000-000000000000',
};