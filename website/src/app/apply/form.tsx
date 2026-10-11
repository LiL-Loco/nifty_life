'use client';

import Link from 'next/link';
import { useActionState, useState } from 'react';

import {
  RULEBOOK_ACKNOWLEDGEMENTS,
  RULEBOOK_SECTIONS,
  RULEBOOK_URL,
} from '@/lib/rulebook';
import { submit, type ApplyState } from './actions';

type Field = 'age' | 'timezone' | 'experience' | 'motivation';

/**
 * One screen per question.
 *
 * Four short screens with one question each is a materially different ask from
 * one long form: nobody abandons a page that asks for a single thing, and a
 * reviewer reading the stored JSON gets the same data either way.
 *
 * The step guard is a convenience, never the check. `validateAnswers` runs the
 * same rules again on the server against a FormData the client fully controls.
 */
export default function ApplicationWizard() {
  const [state, action] = useActionState<ApplyState, FormData>(submit, undefined);
  const [step, setStep] = useState(0);
  const [values, setValues] = useState<Record<Field, string>>({
    age: '',
    timezone: '',
    experience: '',
    motivation: '',
  });
  const [rulebookRead, setRulebookRead] = useState(false);
  const [accepted, setAccepted] = useState<Record<string, boolean>>({});
  const [stepError, setStepError] = useState<string | null>(null);

  const TOTAL_STEPS = 6; // 4 questions + rulebook + review

  function set(field: Field, value: string) {
    setValues((previous) => ({ ...previous, [field]: value }));
    setStepError(null);
  }

  /** Can the current step be left? Mirrors the server rules, minus the wording. */
  function currentStepValid(): true | string {
    switch (step) {
      case 0: {
        const age = values.age.trim();
        if (!/^\d{1,2}$/.test(age) || Number(age) < 18 || Number(age) > 99) {
          return 'Das Alter muss eine Zahl zwischen 18 und 99 sein.';
        }
        return true;
      }
      case 1:
        return values.timezone.trim() ? true : 'Bitte gib deine Zeitzone an.';
      case 2:
        return values.experience.trim() ? true : 'Erzähl uns kurz, was du gespielt hast.';
      case 3:
        return values.motivation.trim() ? true : 'Sag uns, warum du hier spielen willst.';
      case 4: {
        if (!rulebookRead) return 'Bitte bestätige, dass du das Regelwerk gelesen hast.';
        const missing = RULEBOOK_ACKNOWLEDGEMENTS.filter((a) => !accepted[a.key]);
        if (missing.length > 0) {
          return 'Bitte bestätige alle Punkte mit dauerhaftem Ban.';
        }
        return true;
      }
      default:
        return true;
    }
  }

  function next() {
    const verdict = currentStepValid();
    if (verdict !== true) {
      setStepError(verdict);
      return;
    }
    setStepError(null);
    setStep((s) => Math.min(s + 1, TOTAL_STEPS - 1));
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

        {step === 0 ? (
          <Step title="Wie alt bist du?" hint="Ab 18 Jahren.">
            <input
              id="age"
              name="age"
              inputMode="numeric"
              maxLength={2}
              value={values.age}
              onChange={(e) => set('age', e.target.value)}
              autoFocus
            />
          </Step>
        ) : null}

        {step === 1 ? (
          <Step title="In welcher Zeitzone bist du?" hint="Damit wir wissen, wann du mitspielen kannst.">
            <input
              id="timezone"
              name="timezone"
              placeholder="Europe/Berlin"
              maxLength={64}
              value={values.timezone}
              onChange={(e) => set('timezone', e.target.value)}
              autoFocus
            />
          </Step>
        ) : null}

        {step === 2 ? (
          <Step title="Was hast du vorher gespielt?" hint="Server, Mods, oder einfach fünfM Roleplay. Ein paar Sätze reichen.">
            <textarea
              id="experience"
              name="experience"
              maxLength={2000}
              value={values.experience}
              onChange={(e) => set('experience', e.target.value)}
              autoFocus
            />
          </Step>
        ) : null}

        {step === 3 ? (
          <Step title="Warum willst du hier spielen?" hint="Sehr ehrlich. Niemand erwartet einen gepflegten Aufsatz.">
            <textarea
              id="motivation"
              name="motivation"
              maxLength={2000}
              value={values.motivation}
              onChange={(e) => set('motivation', e.target.value)}
              autoFocus
            />
          </Step>
        ) : null}

        {step === 4 ? (
          <Step
            title="Regelwerk"
            hint="Lies es im Link, und bestätige danach die Punkte mit dauerhaftem Ban."
            wide
          >
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

              <label className="small" style={{ display: 'flex', gap: '0.5rem', alignItems: 'flex-start', marginTop: '1rem' }}>
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

            <p className="small muted" style={{ marginTop: '1rem' }}>
              Diese vier Punkte führen jeweils zu einem dauerhaften Ban. Bitte
              bestätige sie einzeln:
            </p>

            {RULEBOOK_ACKNOWLEDGEMENTS.map((item) => (
              <label
                key={item.key}
                className="small"
                style={{ display: 'flex', gap: '0.5rem', alignItems: 'flex-start', marginBottom: '0.6rem' }}
              >
                <input
                  type="checkbox"
                  name="rulebook_ack"
                  value={item.key}
                  style={{ width: 'auto', marginTop: '0.2rem' }}
                  checked={Boolean(accepted[item.key])}
                  onChange={(e) =>
                    setAccepted((previous) => ({ ...previous, [item.key]: e.target.checked }))
                  }
                />
                <span>{item.label}</span>
              </label>
            ))}
          </Step>
        ) : null}

        {step === 5 ? (
          <Step title="Prüfen und abschicken" hint="So wird deine Bewerbung gespeichert.">
            <dl className="small">
              <Review label="Alter">{values.age}</Review>
              <Review label="Zeitzone">{values.timezone}</Review>
              <Review label="Gespielt">{values.experience}</Review>
              <Review label="Motivation">{values.motivation}</Review>
              <Review label="Regelwerk">
                gelesen, alle vier Punkte mit Permaban bestätigt
              </Review>
            </dl>

            <p className="small muted">
              Mit dem Absenden bestätigst du die Angaben. Diese Website kann dich
              nicht freigeben und die Bewerbung danach nicht mehr ändern — das macht
              ein Mensch in Discord.
            </p>
          </Step>
        ) : null}

        <div style={{ display: 'flex', gap: '0.75rem', marginTop: '1.5rem' }}>
          {step > 0 ? (
            <button type="button" className="secondary" onClick={back}>
              Zurück
            </button>
          ) : null}

          {step < TOTAL_STEPS - 1 ? (
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