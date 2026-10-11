import Link from 'next/link';
import { notFound } from 'next/navigation';

import { application } from '@/lib/admin';
import {
  AnswerBody,
  AnswerNumber,
  AnswerPair,
  Answers,
  Card,
} from '@/components/ui';
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
      <p className="text-sm text-muted">
        <Link href="/admin">← zurück zur Übersicht</Link>
      </p>

      <h1 className="mb-1">
        Bewerbung <span className="text-muted">#{row.id.slice(0, 8)}</span>
      </h1>

      <dl className="mb-8 text-sm">
        <dt className={term}>Bewerber</dt>
        <dd className={value}>
          {row.email ?? (
            <span className="font-normal text-muted">kein Portal-Konto</span>
          )}{' '}
          <span className="font-mono">{row.discord_id}</span>
        </dd>

        <dt className={term}>Eingegangen</dt>
        <dd className={value}>{String(row.submitted_at).replace('T', ' ').slice(0, 16)}</dd>

        <dt className={term}>Status</dt>
        <dd className={value}>{LABELS[row.status] ?? row.status}</dd>

        {row.reviewed_at ? (
          <>
            <dt className={term}>Entschieden</dt>
            <dd className={value}>
              {String(row.reviewed_at).replace('T', ' ').slice(0, 16)}
              {row.reviewed_by_discord_id ? ` von ${row.reviewed_by_discord_id}` : ''}
            </dd>
          </>
        ) : null}

        {row.decision_note ? (
          <>
            <dt className={term}>Interne Notiz</dt>
            <dd className={`${value} whitespace-pre-wrap font-normal`}>{row.decision_note}</dd>
          </>
        ) : null}

        {payload.rulebook ? (
          <>
            <dt className={term}>Regelwerk</dt>
            <dd className={value}>
              gelesen am {payload.rulebook.at.slice(0, 10)} · Version{' '}
              {payload.rulebook.version}
            </dd>
          </>
        ) : null}
      </dl>

      <h2>Antworten ({answers.length})</h2>

      {answers.length === 0 ? (
        <Card>
          <p className="mb-0 text-sm text-muted">
            Diese Bewerbung enthält keine auswertbaren Antworten. Prüf das Format,
            bevor du entscheidest.
          </p>
        </Card>
      ) : (
        <Answers>
          {answers.map((answer, index) => (
            <AnswerPair key={answer.id}>
              <div className="flex items-baseline gap-2.5 font-medium">
                <AnswerNumber>{index + 1}</AnswerNumber>
                <span className="flex-1">{answer.question}</span>
              </div>
              <AnswerBody>{answer.answer}</AnswerBody>
            </AnswerPair>
          ))}
        </Answers>
      )}

      <h2>Entscheidung</h2>
      <Card>
        <DecisionForm id={row.id} status={row.status} />
      </Card>
    </>
  );
}

const term = 'mt-3 text-muted';

const value = 'mt-0 mb-0 font-mono';