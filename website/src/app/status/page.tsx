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
  submitted: 'Submitted',
  under_review: 'Under review',
  approved: 'Approved',
  rejected: 'Rejected',
};

const BLURB: Record<ApplicationStatus, string> = {
  submitted: 'Waiting for a human to pick it up.',
  under_review: 'Someone is reading it right now.',
  approved: 'You can connect when the server opens.',
  rejected: 'Read the note below. You can apply again.',
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
      <h1>Your application</h1>
      <p className="lede">
        Discord ID <span className="small">{session.discordId}</span>
      </p>

      {params.submitted ? (
        <div className="notice ok">Application received. A human will read it.</div>
      ) : null}

      {ban ? (
        <div className="notice error">
          <strong>There is an active ban on this account.</strong>
          <br />
          {ban.reason ? <span>{ban.reason} — </span> : null}
          {ban.expires_at ? `Expires ${ban.expires_at}.` : 'No expiry.'}
        </div>
      ) : null}

      {!application ? (
        <div className="card">
          <p>You have not applied yet.</p>
          <Link className="button" href="/apply">
            Apply
          </Link>
        </div>
      ) : (
        <>
          <div className="card">
            <div className="post-head">
              <strong>Current application</strong>
              <span className={`status-pill ${application.status}`}>
                {LABELS[application.status]}
              </span>
            </div>
            <p className="muted small" style={{ marginTop: 0 }}>
              {BLURB[application.status]} Submitted {application.submitted_at}.
            </p>

            {application.decision_note ? (
              <p className="small">
                <strong>Note:</strong> {application.decision_note}
              </p>
            ) : null}

            {application.status === 'approved' && !ban ? (
              <p className="small">
                Connect with <code>connect 127.0.0.1:30120</code> during the weekend
                window.
              </p>
            ) : null}
          </div>

          {history.length > 1 ? (
            <>
              <h2>Earlier applications</h2>
              {history.slice(1).map((row) => (
                <div className="card small" key={row.id}>
                  <span className={`status-pill ${row.status}`}>{LABELS[row.status]}</span>{' '}
                  <span className="muted">submitted {row.submitted_at}</span>
                  {row.decision_note ? (
                    <div className="muted">{row.decision_note}</div>
                  ) : null}
                </div>
              ))}
            </>
          ) : null}
        </>
      )}

      <h2>What this page cannot do</h2>
      <p className="small muted">
        There is no button here to approve an application, because the database
        account this site connects with has no UPDATE privilege on any table. That is
        a property of the grant, not of this interface.
      </p>
    </>
  );
}