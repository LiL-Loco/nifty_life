'use client';

import Link from 'next/link';
import { useActionState, useState } from 'react';

import { RULEBOOK_QUESTIONS, RULEBOOK_SECTIONS, RULEBOOK_URL } from '@/lib/rulebook';
import { submit, type ApplyState } from './actions';

/** Mirrors LIMITS.answerMin in src/lib/applications.ts. */
const ANSWER_MIN = 25;
const ANSWER_MAX = 2000;

const TOTAL_STEPS = RULEBOOK_QUESTIONS.length + 2; // 20 questions + rulebook + review
const RULEBOOK_STEP = RULEBOOK_QUESTIONS.length;
const REVIEW_STEP = RULEBOOK_QUESTIONS.length + 1;

/**
 * One screen per question.
 *
 * Twenty short screens is a materially different ask from one long form: nobody
 * abandons a page that asks for a single thing, and the answers stay short
 * because each one has a single question in front of it.
 *
 * The step guard is a convenience, never the check. `validateAnswers` runs the
 * same rules again on the server against a FormData the client fully controls.
 */
export default function ApplicationWizard() {
  const [state, action] = useActionState<ApplyState, FormData>(submit, undefined);
  const [step, setStep] = useState(0);
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [rulebookRead, setRulebookRead] = useState(false);
  const [stepError, setStepError] = useState<string | null>(null);

  const question = RULEBOOK_QUESTIONS[step];

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

    const answer = (answers[question.id] ?? '').trim();
    if (answer.length === 0) {
      return 'Beantworte diese Frage in eigenen Worten.';
    }
    if (answer.length < ANSWER_MIN) {
      return 'Ein bisschen ausführlicher bitte — ein Satz in eigenen Worten.';
    }

    return true;
  }

  function next() {
    const verdict = currentStepValid();
    if (verdict !== true) {
      setStepError(verdict);
      return;
    }
    setStepError(null);
    setStep((s) => Math.min(s + 1, REVIEW_STEP));
  }

  function back() {
    setStepError(null);
    setStep((s) => Math.max(s - 1, 0));
  }

  return (
    <div>
      <Progress current={step} total={TOTAL_STEPS} />

      {/* One <form> for the whole wizard. Every input stays mounted so the
          browser keeps what was typed when the applicant steps back. */}
      <form action={action}>
        {state?.error ? <div className="notice error">{state.error}</div> : null}
        {stepError ? <div className="notice error">{stepError}</div> : null}

        {question ? (
          <Step
            title={question.question}
            hint={`${question.ref} — antworte in eigenen Worten. Ein bis drei Sätze reichen.`}
            wide
          >
            <textarea
              id={`answer_${question.id}`}
              name={`answer_${question.id}`}
              maxLength={ANSWER_MAX}
              rows={6}
              value={answers[question.id] ?? ''}
              onChange={(e) => setAnswer(question.id, e.target.value)}
              autoFocus
            />
            <p className="small muted" style={{ marginTop: '0.5rem' }}>
              Frage {step + 1} von {RULEBOOK_QUESTIONS.length} — beantworte sie aus dem
              Regelwerk, nicht aus dem Internet.
            </p>
          </Step>
        ) : null}

        {step === RULEBOOK_STEP ? (
          <Step title="Regelwerk" hint="Lies es einmal komplett, dann bestätige es." wide>
            <div className="card" style={{ background: 'var(--ground)' }}>
              <p className="small">
                Das vollständige Regelwerk liegt als Google-Dokument vor:{' '}
                <a href={RULEBOOK_URL} target="_blank" rel="noreferrer noopener">
                  Regelwerk öffnen
                </a>
                .
              </p>

              <p className="small muted">Es besteht aus:</p>
              <ul className="small muted">
                {RULEBOOK_SECTIONS.map((section) => (
                  <li key={section.ref}>
                    <strong>{section.ref}</strong> {section.title}
                  </li>
                ))}
              </ul>

              <label
                className="small"
                style={{ display: 'flex', gap: '0.5rem', alignItems: 'flex-start', marginTop: '1rem' }}
              >
                <input
                  type="checkbox"
                  name="rulebook_read"
                  style={{ width: 'auto', marginTop: '0.2rem' }}
                  checked={rulebookRead}
                  onChange={(e) => setRulebookRead(e.target.checked)}
                />
                <span>Ich habe das vollständige Regelwerk gelesen und verstanden.</span>
              </label>
            </div>
          </Step>
        ) : null}

        {step === REVIEW_STEP ? (
          <Step title="Prüfen und abschicken" hint="So wird deine Bewerbung gespeichert." wide>
            <dl className="small">
              {RULEBOOK_QUESTIONS.map((item, index) => (
                <Review key={item.id} label={`${item.ref} · Frage ${index + 1}`}>
                  {answers[item.id] ?? ''}
                </Review>
              ))}
              <Review label="Regelwerk">gelesen und bestätigt</Review>
            </dl>

            <p className="small muted">
              Mit dem Absenden bestätigst du die Angaben. Eine Bewerbung kann nur
              einmal eingereicht werden — danach entscheidet ein Mensch in Discord,
              und zwar endgültig.
            </p>
          </Step>
        ) : null}

        <div style={{ display: 'flex', gap: '0.75rem', marginTop: '1.5rem' }}>
          {step > 0 ? (
            <button type="button" className="secondary" onClick={back}>
              Zurück
            </button>
          ) : null}

          {step < REVIEW_STEP ? (
            <button type="button" onClick={next}>
              Weiter
            </button>
          ) : (
            <button type="submit">Bewerbung abschicken</button>
          )}
        </div>

        <p className="small muted" style={{ marginTop: '1rem' }}>
          Den <Link href="/status">Status</Link> deiner Bewerbung kannst du jederzeit
          abrufen.
        </p>
      </form>
    </div>
  );
}

function Progress({ current, total }: { current: number; total: number }) {
  return (
    <div className="small muted" style={{ marginBottom: '1.5rem' }}>
      Schritt {current + 1} von {total}
      <div
        style={{
          height: '3px',
          background: 'var(--line)',
          borderRadius: '2px',
          marginTop: '0.5rem',
        }}
      >
        <div
          style={{
            height: '3px',
            width: `${((current + 1) / total) * 100}%`,
            background: 'var(--accent)',
            borderRadius: '2px',
          }}
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
    <div className="card">
      <h2 style={{ marginTop: 0 }}>{title}</h2>
      {hint ? (
        <p className="small muted" style={{ marginTop: '-0.35rem' }}>
          {hint}
        </p>
      ) : null}
      <div style={wide ? undefined : { maxWidth: '28rem' }}>{children}</div>
    </div>
  );
}

function Review({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <>
      <dt style={{ color: 'var(--muted)', marginTop: '0.75rem' }}>{label}</dt>
      <dd style={{ margin: 0, whiteSpace: 'pre-wrap' }}>{children}</dd>
    </>
  );
}