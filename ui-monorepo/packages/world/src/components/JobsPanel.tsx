import * as React from 'react';
import { Button } from '@nifty/ui';
import { send, type JobAssignment, type JobCatalogueEntry } from '../contract';
import { formatMoney } from '../format';

type RosterEntry = JobCatalogueEntry | JobAssignment;

/**
 * Jobs.
 *
 * The roster is the server's whole job list, not just what this character has
 * signed up for — otherwise a character who has never taken a job sees an
 * empty panel and no way out of it. The server decides whether a join succeeds;
 * this panel only offers it.
 *
 * A catalogue entry carries a wage; an assignment does not. When the catalogue
 * has not arrived yet the panel falls back to the assignment list and the wage
 * lays out as 0,00 — the same thing the old panel drew, rather than a dash
 * pretending to know a number it does not have.
 */
export function JobsPanel({
  jobs,
  catalogue,
}: {
  jobs: JobAssignment[];
  catalogue: JobCatalogueEntry[];
}) {
  const assignments = React.useMemo(() => {
    const map = new Map<string, JobAssignment>();
    for (const job of jobs) map.set(job.code, job);
    return map;
  }, [jobs]);

  const roster: RosterEntry[] = catalogue.length ? catalogue : jobs;

  if (!roster.length) {
    return <p className="m-0 text-sm text-[rgba(242,242,240,0.5)]">Keine Jobs verfügbar.</p>;
  }

  return (
    <ul className="m-0 list-none p-0">
      {roster.map((job) => {
        const joined = assignments.get(job.code);
        const wage = 'wagePerHour' in job ? job.wagePerHour : undefined;

        return (
          <li
            key={job.code}
            className="flex items-center gap-3 border-b border-[rgba(255,255,255,0.05)] py-2.5 last:border-b-0"
          >
            <span className="flex-1 text-sm text-[var(--color-foreground)]">
              {job.name}
            </span>
            <span className="text-xs tabular-nums text-[rgba(242,242,240,0.55)]">
              {formatMoney(wage)}/h
            </span>

            {!joined ? (
              <Button
                size="sm"
                onClick={() => {
                  void send('jobJoin', { code: job.code });
                }}
              >
                Anmelden
              </Button>
            ) : joined.onDuty ? (
              <Button
                size="sm"
                onClick={() => {
                  void send('dutyEnd', { code: job.code });
                }}
              >
                Schicht beenden
              </Button>
            ) : (
              <>
                <Button
                  size="sm"
                  onClick={() => {
                    void send('dutyStart', { code: job.code });
                  }}
                >
                  Schicht beginnen
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => {
                    void send('jobLeave', { code: job.code });
                  }}
                >
                  Kündigen
                </Button>
              </>
            )}
          </li>
        );
      })}
    </ul>
  );
}