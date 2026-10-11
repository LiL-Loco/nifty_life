import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentSession } from '@/lib/auth';
import {
  activeBan,
  applicationHistory,
  latestApplication,
  type ApplicationStatus,
} from '@/lib/applications';

const LABELS: Record<ApplicationStatus, string> = {
  submitted: 'Eingegangen',
  under_review: 'In Prüfung',
  approved: 'Freigegeben',
  rejected: 'Abgelehnt',
};

const BLURB: Record<ApplicationStatus, string> = {
  submitted: 'Wartet darauf, dass sich ein Mensch die Bewerbung ansieht.',
  under_review: 'Gerade wird sie gelesen.',
  approved: 'Du kannst dich verbinden, sobald der Server offen ist.',
  rejected: 'Lies die Nachricht unten. Du kannst dich erneut bewerben.',
};

export default async function StatusPage({
  searchParams,
}: {
  searchParams: Promise<{ submitted?: string }>;
}) {
  const [session, params] = await Promise.all([currentSession(), searchParams]);
  if (!session) redirect('/');

  const [application, history, ban] = await Promise.all([
    latestApplication(session.discordId),
    applicationHistory(session.discordId),
    activeBan(session.discordId),
  ]);

  return (
    <>
      <h1>Deine Bewerbung</h1>
      <p className="lede">
        Discord-ID <span className="small">{session.discordId}</span>
      </p>

      {params.submitted ? (
        <div className="notice ok">
          Bewerbung eingegangen. Ein Mensch wird sie lesen.
        </div>
      ) : null}

      {ban ? (
        <div className="notice error">
          <strong>Auf diesem Konto ist ein aktives Ban hinterlegt.</strong>
          <br />
          {ban.reason ? <span>{ban.reason} — </span> : null}
          {ban.expires_at ? `Läuft ab am ${ban.expires_at}.` : 'Ohne Ablaufdatum.'}
        </div>
      ) : null}

      {!application ? (
        <div className="card">
          <p>Du hast dich noch nicht beworben.</p>
          <Link className="button" href="/apply">
            Bewerben
          </Link>
        </div>
      ) : (
        <>
          <div className="card">
            <div className="post-head">
              <strong>Aktuelle Bewerbung</strong>
              <span className={`status-pill ${application.status}`}>
                {LABELS[application.status]}
              </span>
            </div>
            <p className="muted small" style={{ marginTop: 0 }}>
              {BLURB[application.status]} Eingegangen am {application.submitted_at}.
            </p>

            {application.decision_note ? (
              <p className="small">
                <strong>Nachricht:</strong> {application.decision_note}
              </p>
            ) : null}

            {application.status === 'approved' && !ban ? (
              <p className="small">
                Verbinde dich während des Zeitfensters mit{' '}
                <code>connect 127.0.0.1:30120</code>.
              </p>
            ) : null}
          </div>

          {history.length > 1 ? (
            <>
              <h2>Frühere Bewerbungen</h2>
              {history.slice(1).map((row) => (
                <div className="card small" key={row.id}>
                  <span className={`status-pill ${row.status}`}>
                    {LABELS[row.status]}
                  </span>{' '}
                  <span className="muted">eingegangen am {row.submitted_at}</span>
                  {row.decision_note ? (
                    <div className="muted">{row.decision_note}</div>
                  ) : null}
                </div>
              ))}
            </>
          ) : null}
        </>
      )}

      <h2>Was diese Seite nicht kann</h2>
      <p className="small muted">
        Hier gibt es keinen Knopf, um eine Bewerbung freizugeben — der
        Datenbankzugang dieser Seite besitzt auf keinerlei Tabelle ein UPDATE-Recht.
        Das ist eine Eigenschaft der Rechtevergabe, nicht dieser Oberfläche.
      </p>
    </>
  );
}