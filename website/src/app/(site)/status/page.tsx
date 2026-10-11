import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import {
  activeBan,
  applicationHistory,
  latestApplication,
  type ApplicationStatus,
} from '@/lib/applications';
import { Card, Notice, StatusPill, buttonLinkClass } from '@/components/ui';

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

/**
 * The status of THIS person's application.
 *
 * Looked up by account OR by Discord ID, because the account is the login but
 * the Discord ID is what the game server knows. Keying on both is what lets
 * somebody who registered today still see an application they filed through the
 * old Discord login last week.
 */
export default async function StatusPage({
  searchParams,
}: {
  searchParams: Promise<{ submitted?: string }>;
}) {
  const [account, params] = await Promise.all([currentAccount(), searchParams]);
  if (!account) redirect('/login');

  const discordId = account.discord?.discordId ?? null;

  // A ban is keyed on the Discord ID, so with no link there is nothing that can
  // be banned and nothing to look up. Asking anyway with a NULL would return no
  // rows and read as "not banned" — technically true and quietly misleading.
  const [application, history, ban] = await Promise.all([
    latestApplication(account.user.id, discordId),
    applicationHistory(account.user.id, discordId),
    discordId ? activeBan(discordId) : Promise.resolve(null),
  ]);

  return (
    <>
      <h1>Deine Bewerbung</h1>
      <p className="mb-8 text-muted">
        {account.user.email}
        {account.discord ? (
          <>
            {' · '}Discord <span className="text-xs">{account.discord.discordId}</span>
          </>
        ) : (
          <>
            {' · '}
            <Link href="/account">kein Discord-Konto verknüpft</Link>
          </>
        )}
      </p>

      {params.submitted ? (
        <Notice tone="ok">
          Bewerbung eingegangen. Ein Mensch wird sie lesen.
        </Notice>
      ) : null}

      {ban ? (
        <Notice tone="error" role="alert">
          <strong>Auf diesem Konto ist ein aktives Ban hinterlegt.</strong>
          <br />
          {ban.reason ? <span>{ban.reason} - </span> : null}
          {ban.expires_at ? `Läuft ab am ${ban.expires_at}.` : 'Ohne Ablaufdatum.'}
        </Notice>
      ) : null}

      {!application ? (
        <Card>
          <p>Du hast dich noch nicht beworben.</p>
          <Link className={buttonLinkClass()} href="/apply">
            Bewerben
          </Link>
        </Card>
      ) : (
        <>
          <Card>
            <div className="mb-1.5 flex justify-between gap-4 text-sm">
              <strong>Aktuelle Bewerbung</strong>
              <StatusPill tone={application.status}>{LABELS[application.status]}</StatusPill>
            </div>
            <p className="mb-0 mt-0 text-sm text-muted">
              {BLURB[application.status]} Eingegangen am {application.submitted_at}.
            </p>

            {application.decision_note ? (
              <p className="text-sm">
                <strong>Nachricht:</strong> {application.decision_note}
              </p>
            ) : null}

            {application.status === 'approved' && !ban ? (
              <p className="text-sm">
                Verbinde dich während des Zeitfensters mit{' '}
                <code>connect 127.0.0.1:30120</code>.
              </p>
            ) : null}
          </Card>

          {history.length > 1 ? (
            <>
              <h2>Frühere Bewerbungen</h2>
              {history.slice(1).map((row) => (
                <Card className="text-sm" key={row.id}>
                  <StatusPill tone={row.status}>{LABELS[row.status]}</StatusPill>{' '}
                  <span className="text-muted">eingegangen am {row.submitted_at}</span>
                  {row.decision_note ? (
                    <div className="text-muted">{row.decision_note}</div>
                  ) : null}
                </Card>
              ))}
            </>
          ) : null}
        </>
      )}

      <h2>Was diese Seite nicht kann</h2>
      <p className="text-sm text-muted">
        Hier gibt es keinen Knopf, um eine Bewerbung freizugeben - der
        Datenbankzugang dieser Seite besitzt auf keinerlei Tabelle ein UPDATE-Recht.
        Das ist eine Eigenschaft der Rechtevergabe, nicht dieser Oberfläche.
      </p>
    </>
  );
}