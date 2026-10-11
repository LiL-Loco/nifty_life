import Link from 'next/link';
import { notFound } from 'next/navigation';

import { application } from '@/lib/admin';
import DecisionForm from './decision-form';

export const dynamic = 'force-dynamic';

const LABELS: Record<string, string> = {
  submitted: 'neu',
  under_review: 'in Prüfung',
  approved: 'freigegeben',
  rejected: 'abgelehnt',
};

interface StoredAnswer {
  id: string;
  question: string;
  answer: string;
}

interface StoredPayload {
  rulebook?: { read: boolean; at: string; version: string };
  answers?: StoredAnswer[];
}

export default async function AdminApplication({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const row = await application(id);

  if (!row) notFound();

  // mysql2 parses JSON columns into objects on the way out, but the shape is not
  // guaranteed across driver paths. Accept both rather than asserting one the
  // database does not promise.
  const raw = (row as { answers: unknown }).answers;
  const payload: StoredPayload = typeof raw === 'string' ? JSON.parse(raw) : (raw as StoredPayload);
  const answers = payload.answers ?? [];

  return (
    <>
      <p className="small muted">
        <Link href="/admin">← zurück zur Übersicht</Link>
      </p>

      <h1 style={{ marginBottom: '0.25rem' }}>
        Bewerbung <span style={{ color: 'var(--muted)' }}>#{row.id.slice(0, 8)}</span>
      </h1>

      <dl className="small" style={{ marginBottom: '2rem' }}>
        <dt style={label}>Bewerber</dt>
        <dd style={value}>{row.discord_id}</dd>

        <dt style={label}>Eingegangen</dt>
        <dd style={value}>{String(row.submitted_at).replace('T', ' ').slice(0, 16)}</dd>

        <dt style={label}>Status</dt>
        <dd style={value}>{LABELS[row.status] ?? row.status}</dd>

        {row.reviewed_at ? (
          <>
            <dt style={label}>Entschieden</dt>
            <dd style={value}>
              {String(row.reviewed_at).replace('T', ' ').slice(0, 16)}
              {row.reviewed_by_discord_id ? ` von ${row.reviewed_by_discord_id}` : ''}
            </dd>
          </>
        ) : null}

        {row.decision_note ? (
          <>
            <dt style={label}>Interne Notiz</dt>
            <dd style={{ ...value, whiteSpace: 'pre-wrap' }}>{row.decision_note}</dd>
          </>
        ) : null}

        {payload.rulebook ? (
          <>
            <dt style={label}>Regelwerk</dt>
            <dd style={value}>
              gelesen am {payload.rulebook.at.slice(0, 10)} · Version{' '}
              {payload.rulebook.version}
            </dd>
          </>
        ) : null}
      </dl>

      <h2>Antworten ({answers.length})</h2>

      {answers.length === 0 ? (
        <div className="card">
          <p className="small muted">
            Diese Bewerbung enthält keine auswertbaren Antworten. Prüf das Format,
            bevor du entscheidest.
          </p>
        </div>
      ) : (
        <ol className="answers">
          {answers.map((answer, index) => (
            <li key={answer.id}>
              <div className="q">
                <span className="q-num">{index + 1}</span>
                <span className="q-text">{answer.question}</span>
              </div>
              <div className="a">{answer.answer}</div>
            </li>
          ))}
        </ol>
      )}

      <h2>Entscheidung</h2>
      <div className="card">
        <DecisionForm id={row.id} status={row.status} />
      </div>
    </>
  );
}

const label: React.CSSProperties = {
  color: 'var(--muted)',
  marginTop: '0.75rem',
};

const value: React.CSSProperties = {
  margin: 0,
  fontFamily: 'monospace',
};