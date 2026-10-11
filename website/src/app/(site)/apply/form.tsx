'use client';

import Link from 'next/link';
import { useActionState, useCallback, useEffect, useRef, useState } from 'react';

import { RULEBOOK_QUESTIONS, RULEBOOK_SECTIONS, RULEBOOK_URL } from '@/lib/rulebook';
import { Button, Card, Notice } from '@/components/ui';
import { submit, type ApplyState } from './actions';

/** Mirrors LIMITS.answerMin in src/lib/applications.ts. */
const ANSWER_MIN = 25;
const ANSWER_MAX = 2000;

/** The key answers are kept under between steps and page loads. */
const STORAGE_KEY = 'nifty.answers.v2';

const TOTAL_STEPS = RULEBOOK_QUESTIONS.length + 2;
const RULEBOOK_STEP = RULEBOOK_QUESTIONS.length;
const REVIEW_STEP = RULEBOOK_QUESTIONS.length + 1;

interface Draft {
  answers: Record<string, string>;
  rulebookRead: boolean;
}

/**
 * The draft lives in localStorage, and that is the whole point of it.
 *
 * Twenty answers is roughly a page of typing. Without a draft, closing the tab or
 * a stray reload loses the lot, and somebody who has spent half an hour on this
 * will not do it twice. It is also what makes "the answer is saved when you click
 * Weiter" true rather than aspirational — React state dies with the tab.
 *
 * localStorage, not the server: an abandoned draft is not worth a database table,
 * and a draft on the server would have to be either anonymous (then anyone can
 * read it) or tied to a session (then it survives nothing anyway).
 */
function loadDraft(): Draft {
  const empty: Draft = { answers: {}, rulebookRead: false };
  if (typeof window === 'undefined') return empty;

  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return empty;
    const parsed = JSON.parse(raw) as Partial<Draft>;
    return {
      answers: typeof parsed.answers === 'object' && parsed.answers !== null ? parsed.answers : {},
      rulebookRead: parsed.rulebookRead === true,
    };
  } catch {
    // A corrupt or unreadable draft must never block the form. The worst case
    // of ignoring it is typing twenty answers twice, which is still better than
    // a blank page with an error.
    return empty;
  }
}

function saveDraft(draft: Draft): void {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(draft));
  } catch {
    // Private mode, quota, or storage disabled. The answers are still in React
    // state, so the form keeps working for this session.
  }
}

/**
 * One screen per question.
 *
 * Twenty short screens is a materially different ask from one long form: nobody
 * abandons a page that asks for a single thing, and the answers stay short
 * because each one has a single question in front of it.
 *
 * EMPTY IS ALLOWED TO PASS. Clicking Weiter with a blank box moves on rather
 * than trapping you, because a form that will not let you leave screen nine is a
 * form people abandon. The price is that you can reach the end with blanks — so
 * the SUBMIT is what enforces completeness, and it says exactly which questions
 * are missing instead of just refusing.
 *
 * The step guard is a convenience, never the check. `validateAnswers` runs the
 * same rules again on the server against a FormData the client fully controls.
 */
export default function ApplicationWizard() {
  const [state, action] = useActionState<ApplyState, FormData>(submit, undefined);
  const [step, setStep] = useState(0);
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [rulebookRead, setRulebookRead] = useState(false);
  const [restored, setRestored] = useState(false);
  const [stepError, setStepError] = useState<string | null>(null);
  const [ackOwnWords, setAckOwnWords] = useState(false);

  // Restored once, after mount. Reading localStorage during render would make
  // the first paint differ from every later one — a hydration mismatch, and the
  // answers would visibly jump into the box.
  useEffect(() => {
    const draft = loadDraft();
    setAnswers(draft.answers);
    setRulebookRead(draft.rulebookRead);
    setRestored(Object.keys(draft.answers).length > 0 || draft.rulebookRead);
  }, []);

  const question = RULEBOOK_QUESTIONS[step];

  // Persist on every change, not only on "Weiter". The click is the promised
  // moment, but an answer typed and then closed with the X must not vanish
  // either, and a single effect covers both cases without two code paths.
  useEffect(() => {
    if (!restored) return;
    saveDraft({ answers, rulebookRead });
  }, [answers, rulebookRead, restored]);

  function setAnswer(id: string, value: string) {
    setAnswers((previous) => ({ ...previous, [id]: value }));
    setStepError(null);
  }

  /** Can the current step be left? Mirrors the server rules, minus the wording. */
  function currentStepValid(): true | string {
    if (step >= REVIEW_STEP) return true;

    if (step === RULEBOOK_STEP) {
      if (!rulebookRead) return 'Bitte bestätige, dass du das Regelwerk gelesen hast.';
      return true;
    }

    // Empty passes. A written answer still has to be a written answer.
    const answer = (answers[question.id] ?? '').trim();
    if (answer.length > 0 && answer.length < ANSWER_MIN) {
      return `Zu kurz — mindestens ${ANSWER_MIN} Zeichen, ein Satz in eigenen Worten.`;
    }

    return true;
  }

  const next = useCallback(() => {
    const verdict = currentStepValid();
    if (verdict !== true) {
      setStepError(verdict);
      return;
    }
    // The explicit save the requirement asks for. The effect above already
    // covers it, but this is the moment the applicant was promised, and an
    // explicit save is what makes that promise readable in the code.
    saveDraft({ answers, rulebookRead });
    setStepError(null);
    setStep((s) => Math.min(s + 1, REVIEW_STEP));
  }, [answers, rulebookRead, step]);

  function back() {
    setStepError(null);
    setStep((s) => Math.max(s - 1, 0));
  }

  function startOver() {
    setAnswers({});
    setRulebookRead(false);
    setAckOwnWords(false);
    setRestored(false);
    if (typeof window !== 'undefined') window.localStorage.removeItem(STORAGE_KEY);
  }

  const answered = RULEBOOK_QUESTIONS.filter(
    (item) => (answers[item.id] ?? '').trim().length >= ANSWER_MIN,
  ).length;

  return (
    <div>
      <Progress current={step} total={TOTAL_STEPS} />

      {/* One <form> for the whole wizard. Every input stays mounted so the
          browser keeps what was typed when the applicant steps back. */}
      <form action={action}>
        {state?.error ? (
          <Notice tone="error" role="alert">
            {state.error}
          </Notice>
        ) : null}
        {stepError ? (
          <Notice tone="error" role="alert">
            {stepError}
          </Notice>
        ) : null}

        {restored && step === 0 ? (
          <Notice>
            Deine Antworten sind gespeichert. Du machst dort weiter, wo du
            aufgehört hast.
            <Button
              type="button"
              variant="link"
              className="ml-3"
              onClick={startOver}
            >
              Alles verwerfen
            </Button>
          </Notice>
        ) : null}

        {question ? (
          <Step
            title={question.question}
            hint={`${question.ref} — antworte in eigenen Worten. Ein bis drei Sätze reichen.`}
            wide
          >
            <NoPasteTextarea
              id={`answer_${question.id}`}
              name={`answer_${question.id}`}
              maxLength={ANSWER_MAX}
              rows={6}
              value={answers[question.id] ?? ''}
              onChange={(e) => setAnswer(question.id, e.target.value)}
              autoFocus
            />

            <p className="mt-2 mb-0 text-sm text-muted">
              Frage {step + 1} von {RULEBOOK_QUESTIONS.length} ·{' '}
              {(answers[question.id] ?? '').trim().length < ANSWER_MIN ? (
                <>noch {ANSWER_MIN - (answers[question.id] ?? '').trim().length} Zeichen</>
              ) : (
                'wird beim Weiter gespeichert'
              )}
            </p>
          </Step>
        ) : null}

        {step === RULEBOOK_STEP ? (
          <Step title="Regelwerk" hint="Lies es einmal komplett, dann bestätige es." wide>
            <Card className="bg-ground">
              <p className="text-sm">
                Das vollständige Regelwerk liegt als Google-Dokument vor:{' '}
                <a href={RULEBOOK_URL} target="_blank" rel="noreferrer noopener">
                  Regelwerk öffnen
                </a>
                .
              </p>

              <p className="text-sm text-muted">Es besteht aus:</p>
              <ul className="text-sm text-muted">
                {RULEBOOK_SECTIONS.map((section) => (
                  <li key={section.ref}>
                    <strong>{section.ref}</strong> {section.title}
                  </li>
                ))}
              </ul>

              <label className="mt-4 flex items-start gap-2 text-sm">
                <input
                  type="checkbox"
                  name="rulebook_read"
                  className="mt-0.5"
                  checked={rulebookRead}
                  onChange={(e) => setRulebookRead(e.target.checked)}
                />
                <span>Ich habe das vollständige Regelwerk gelesen und verstanden.</span>
              </label>
            </Card>
          </Step>
        ) : null}

        {step === REVIEW_STEP ? (
          <Step title="Prüfen und abschicken" hint="So wird deine Bewerbung gespeichert." wide>
            <p className="mt-0 text-sm text-muted">
              {answered === RULEBOOK_QUESTIONS.length
                ? 'Alle 20 Fragen beantwortet.'
                : `Noch ${RULEBOOK_QUESTIONS.length - answered} von ${RULEBOOK_QUESTIONS.length} Fragen unbeantwortet oder zu kurz.`}
            </p>

            <dl className="text-sm">
              {RULEBOOK_QUESTIONS.map((item, index) => {
                const value = (answers[item.id] ?? '').trim();
                const short = value.length > 0 && value.length < ANSWER_MIN;
                return (
                  <Review
                    key={item.id}
                    label={`${item.ref} · Frage ${index + 1}`}
                    bad={value.length === 0 || short}
                  >
                    {value || (short ? 'zu kurz' : '— noch nicht beantwortet —')}
                  </Review>
                );
              })}
              <Review label="Regelwerk">
                {rulebookRead ? 'gelesen und bestätigt' : 'noch nicht bestätigt'}
              </Review>
            </dl>

            {/* The server raises this on the first submit when answers look
                copied. Ticking it is the applicant's statement that the answers
                are their own — which a moderator weighs, rather than a rule they
                accepted. */}
            {state?.error ? (
              <label className="mt-4 flex items-start gap-2 text-sm">
                <input
                  type="checkbox"
                  name="own_words_ack"
                  className="mt-0.5"
                  checked={ackOwnWords}
                  onChange={(e) => setAckOwnWords(e.target.checked)}
                />
                <span>Die Antworten sind meine eigenen. Ich möchte sie so abschicken.</span>
              </label>
            ) : null}

            <p className="mt-4 text-sm text-muted">
              Eine Bewerbung kann nur einmal eingereicht werden — danach entscheidet
              ein Mensch in Discord, und zwar endgültig.
            </p>
          </Step>
        ) : null}

        <div className="mt-6 flex gap-3">
          {step > 0 ? (
            <Button type="button" variant="secondary" onClick={back}>
              Zurück
            </Button>
          ) : null}

          {step < REVIEW_STEP ? (
            <Button type="button" onClick={next}>
              Weiter
            </Button>
          ) : (
            <Button type="submit" disabled={answered < RULEBOOK_QUESTIONS.length || !rulebookRead}>
              Bewerbung abschicken
            </Button>
          )}
        </div>

        <p className="mt-4 text-sm text-muted">
          Den <Link href="/status">Status</Link> deiner Bewerbung kannst du jederzeit
          abrufen.
        </p>
      </form>
    </div>
  );
}

/**
 * A textarea that refuses pasted and copied text.
 *
 * Three handlers, all preventDefault:
 *
 *   onPaste — blocks text arriving from the clipboard, which is how a rulebook
 *     paragraph gets into the box in one keystroke.
 *   onCopy / onCut — blocks text leaving, which is the other half: without it
 *     the applicant can open the rulebook, select a paragraph and drop it into
 *     the box, and with only onPaste blocked that still works on some paths.
 *
 * This is a speed bump, not a wall. The clipboard API is reachable from the
 * console, and the server check in `validateAnswers` is what actually decides.
 * It is here so that the path the requirement asks about is closed in the
 * browser too, and so an honest applicant gets a nudge instead of a silent
 * success.
 */
function NoPasteTextarea(props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  const ref = useRef<HTMLTextAreaElement>(null);

  const block = useCallback((event: React.ClipboardEvent<HTMLTextAreaElement>) => {
    event.preventDefault();
  }, []);

  const blockDrop = useCallback((event: React.DragEvent<HTMLTextAreaElement>) => {
    event.preventDefault();
  }, []);

  return (
    <textarea
      {...props}
      ref={ref}
      onPaste={block}
      onCopy={block}
      onCut={block}
      onDrop={blockDrop}
    />
  );
}

function Progress({ current, total }: { current: number; total: number }) {
  return (
    <div className="mb-6 text-sm text-muted">
      Schritt {current + 1} von {total}
      <div className="mt-2 h-[3px] rounded-[2px] bg-line">
        <div
          className="h-[3px] rounded-[2px] bg-accent"
          style={{ width: `${((current + 1) / total) * 100}%` }}
        />
      </div>
    </div>
  );
}

function Step({
  title,
  hint,
  wide,
  children,
}: {
  title: string;
  hint?: string;
  wide?: boolean;
  children: React.ReactNode;
}) {
  return (
    <Card>
      <h2 className="mt-0">{title}</h2>
      {hint ? <p className="-mt-1.5 text-sm text-muted">{hint}</p> : null}
      <div className={wide ? undefined : 'max-w-[28rem]'}>{children}</div>
    </Card>
  );
}

function Review({
  label,
  bad,
  children,
}: {
  label: string;
  bad?: boolean;
  children: React.ReactNode;
}) {
  return (
    <>
      <dt className="mt-3 text-muted">{label}</dt>
      <dd
        className={
          bad ? 'm-0 whitespace-pre-wrap text-danger' : 'm-0 whitespace-pre-wrap'
        }
      >
        {children}
      </dd>
    </>
  );
}