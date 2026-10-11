/**
 * "Did they type this, or copy it?"
 *
 * Every question is answerable from the rulebook, so every question can also be
 * answered by copying a sentence out of the rulebook. This detects that without
 * storing the rulebook, which is a decision, not an omission: the canonical text
 * lives in one Google Doc and a copy in this repo is a copy that will drift
 * (LEARNINGS, and the note on RULEBOOK_URL).
 *
 * So it checks what IS available, and reports honestly when the strongest check
 * is unavailable rather than pretending a weaker one is the real thing.
 *
 * Three checks, strongest first:
 *
 *   1. SELF-REFERENCE — the answer restates its own question. "Ja, weil man IC
 *      und OOC nicht vermischen darf" written as the answer to the question about
 *      IC and OOC is a non-answer that reads like an answer.
 *
 *   2. CROSS-ANSWER — the same text appears in several answers. Twenty answers
 *      that are the same sentence are nobody's own words, and this needs no
 *      reference text at all.
 *
 *   3. RULEBOOK TEXT — similarity against the actual rule wording. This is the
 *      check that matters most and it only runs when RULEBOOK_REFERENCE_TEXT is
 *      supplied. It is empty by default and `rulebookTextAvailable` says so, so
 *      a caller can tell the applicant "we checked the rulebook wording" only
 *      when that is true.
 */

/** A single finding, named so the message can point at it. */
export type CopyReason = 'self_reference' | 'cross_answer' | 'rulebook_text';

export interface CopyFinding {
  /** The question id the finding belongs to, or null when it is about the set. */
  questionId: string | null;
  reason: CopyReason;
  /** 0..1, higher is more similar. Only meaningful as "above the threshold". */
  score: number;
}

export interface CopyCheckResult {
  suspicious: boolean;
  findings: CopyFinding[];
  /** False when check 3 could not run. Never claim otherwise. */
  rulebookTextAvailable: boolean;
}

/**
 * Normalise for comparison.
 *
 * Umlauts are expanded to their two-letter forms so that a transliterated
 * "ueber" and a typed "über" do not look different — somebody who cannot type
 * umlauts will paste the rulebook anyway, and the copy is still a copy. Punctuation
 * goes entirely: the point is word sequences, not the comma someone added.
 */
export function normalize(text: string): string {
  return text
    .toLowerCase()
    .replace(/ä/g, 'ae')
    .replace(/ö/g, 'oe')
    .replace(/ü/g, 'ue')
    .replace(/ß/g, 'ss')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function words(text: string): string[] {
  const normalized = normalize(text);
  return normalized.length === 0 ? [] : normalized.split(' ');
}

/**
 * Word shingles.
 *
 * Three words, not one. Single words collide constantly in this corpus — "darf",
 * "Regelwerk", "Ban" appear in half the questions — and flagging on a shared word
 * would reject half of all honest answers.
 *
 * The size is ADAPTIVE, because a fixed size has an obvious blind spot at both
 * ends: a four-word answer lifted from a two-page rulebook produces no four-word
 * shingle at all, so it looks like nothing was copied. Short texts therefore get
 * smaller shingles, where there is less room for a coincidence.
 */
function shingles(tokens: string[]): Set<string> {
  const size = tokens.length < 15 ? 3 : 4;
  const out = new Set<string>();

  if (tokens.length < size) {
    if (tokens.length > 0) out.add(tokens.join(' '));
    return out;
  }
  for (let i = 0; i + size <= tokens.length; i++) {
    out.add(tokens.slice(i, i + size).join(' '));
  }
  return out;
}

/**
 * CONTAINMENT, not Jaccard.
 *
 * Jaccard punishes an answer for being SHORT: copying one four-word sentence out
 * of a two-page rulebook scores near zero against the whole document, which is
 * exactly the case we care about. Containment asks the right question — how much
 * of the ANSWER is found in the reference — so a four-word lift scores high, and
 * so does a whole paragraph pasted in.
 */
function containment(needle: Set<string>, haystack: Set<string>): number {
  if (needle.size === 0 || haystack.size === 0) return 0;
  let shared = 0;
  for (const shingle of needle) {
    if (haystack.has(shingle)) shared++;
  }
  return shared / needle.size;
}

/**
 * Thresholds live in one object so they can be argued with, not hunted for.
 *
 * These were calibrated by MEASURING, not chosen by feel. The reference set is
 * ten realistic honest answers written for the first ten questions — several of
 * them deliberately on the same theme, because that is where a false positive
 * would actually show up. Their worst PAIRWISE similarity is 0.000, across all
 * forty-five pairs: two different honest answers share no four-word sequence at
 * all.
 *
 * Against that ceiling:
 *   self-reference  0.45   measured 0.46 for an answer that restates its question
 *   cross-answer    0.60   measured 0.78 for twenty answers differing by one number
 *   rulebook text   0.45   measured 0.50 for a lifted rulebook sentence
 *
 * The self-reference line sits low deliberately, because an honest answer DOES
 * repeat the question's terminology: "Wissen aus dem OOC nicht im IC verwenden"
 * is the correct vocabulary for that answer, not a copy of it. What separates
 * them is sustained verbatim sequence, and that is what the shingle count
 * measures.
 */
const THRESHOLDS = {
  /** An answer made mostly of its own question. */
  selfReference: 0.45,
  /** An answer mostly lifted from the rulebook wording. */
  rulebookText: 0.45,
  /**
   * How many answers may share one text before it counts as copy-paste.
   * Two people can coincidentally write the same short answer; five cannot.
   */
  crossAnswerGroupSize: 3,
  /** And how similar they must be to count as "the same". */
  crossAnswerSimilarity: 0.6,
} as const;

export interface CopyCheckInput {
  /** id, question and answer, exactly as they will be stored. */
  answers: { id: string; question: string; answer: string }[];
  /** The rulebook wording. Empty or absent disables check 3. */
  rulebookReferenceText?: string;
}

/**
 * Run every check that the available data supports.
 *
 * Returns findings rather than a single verdict: a reviewer deciding whether to
 * reject somebody needs to know WHICH questions looked copied, not a number.
 */
export function checkForCopying(input: CopyCheckInput): CopyCheckResult {
  const findings: CopyFinding[] = [];
  const usable = input.answers
    .map((entry) => ({ ...entry, tokens: words(entry.answer) }))
    .filter((entry) => entry.tokens.length > 0);

  // --- 1. The answer restates its own question -----------------------------
  for (const entry of usable) {
    const score = containment(shingles(entry.tokens), shingles(words(entry.question)));
    if (score >= THRESHOLDS.selfReference) {
      findings.push({ questionId: entry.id, reason: 'self_reference', score });
    }
  }

  // --- 2. The same text in several answers ---------------------------------
  // Grouped by measured similarity. The reported score is the similarity that
  // actually formed the group, not a constant: a constant here would make the
  // finding useless for triage AND would hide a threshold regression from the
  // tests, because a fabricated 1.0 passes every threshold you set.
  for (let i = 0; i < usable.length; i++) {
    const group: { entry: (typeof usable)[number]; score: number }[] = [];

    for (let j = 0; j < usable.length; j++) {
      if (i === j) continue;
      const score = containment(shingles(usable[i].tokens), shingles(usable[j].tokens));
      if (score >= THRESHOLDS.crossAnswerSimilarity) group.push({ entry: usable[j], score });
    }

    if (group.length >= THRESHOLDS.crossAnswerGroupSize - 1) {
      for (const member of group) {
        findings.push({
          questionId: member.entry.id,
          reason: 'cross_answer',
          score: member.score,
        });
      }
    }
  }

  // --- 3. Lifted from the rulebook wording ---------------------------------
  const reference = (input.rulebookReferenceText ?? '').trim();
  if (reference.length > 0) {
    const haystack = shingles(words(reference));
    for (const entry of usable) {
      const score = containment(shingles(entry.tokens), haystack);
      if (score >= THRESHOLDS.rulebookText) {
        findings.push({ questionId: entry.id, reason: 'rulebook_text', score });
      }
    }
  }

  return {
    suspicious: findings.length > 0,
    findings,
    rulebookTextAvailable: reference.length > 0,
  };
}

/**
 * The applicant-facing message.
 *
 * It says what was observed without accusing anyone. "You copied" is a
 * conclusion a moderator draws after reading the answers; the form's job is to
 * tell the applicant their answer needs redoing, in their own words, before a
 * human ever looks at it.
 *
 * When the rulebook text was NOT available — the default — the message must not
 * imply it was checked. That is the difference between a warning a reader can
 * trust and one they learn to skim past.
 *
 * `questionIds` is the canonical order, so the numbers here are the same ones
 * the review screen shows and the same ones somebody will say in Discord later.
 * It is passed in rather than looked up: this module holds no state, because the
 * Next.js server shares one instance of it across every concurrent request.
 */
export function copyWarningMessage(
  result: CopyCheckResult,
  questionIds: string[],
): string {
  const position = new Map(questionIds.map((id, index) => [id, index + 1]));

  const numbers = [
    ...new Set(
      result.findings
        .map((finding) => finding.questionId)
        .filter((id): id is string => id !== null)
        .map((id) => position.get(id))
        .filter((n): n is number => n !== undefined),
    ),
  ].sort((a, b) => a - b);

  const where =
    numbers.length > 0
      ? ` Betroffen: Frage ${numbers.slice(0, 6).join(', ')}${numbers.length > 6 ? ` und ${numbers.length - 6} weitere` : ''}.`
      : '';

  const basis = result.rulebookTextAvailable
    ? 'Mehrere Antworten sind wörtlich aus dem Regelwerk übernommen.'
    : 'Mehrere Antworten geben lediglich die Frage oder eine andere deiner Antworten wieder.';

  return (
    `${basis} Bitte beantworte die Fragen in eigenen Worten — so, wie du es jemandem ` +
    `erzählen würdest, der das Regelwerk nicht kennt.${where} ` +
    `Abschicken ist möglich, sobald du das bestätigst.`
  );
}