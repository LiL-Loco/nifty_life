import type { Metadata } from 'next';
import Link from 'next/link';

import { GLOSSARY, RULEBOOK } from '@/lib/rulebook';
import { buttonVariants } from '@/components/ui';

export const metadata: Metadata = { title: 'Regelwerk — Nifty Life 2.0' };

/**
 * The rulebook, read here.
 *
 * This used to be a link out to a Google Doc. The text is now in the repository
 * (`RULEBOOK` in `src/lib/rulebook.ts`) and rendered below, so an applicant who
 * is about to agree to these rules never leaves the site to do it.
 *
 * The document is still the team's editing surface. What that costs is drift, and
 * it is stated on the page rather than hidden: the last-sync line below tells the
 * reader which text they are agreeing to. A rulebook that silently differs from
 * the one players accepted is worse than no rulebook, so the copy is dated, not
 * presented as the source.
 *
 * Static, like the landing page: nothing here reads the session or the database,
 * and a rulebook a stranger must log in to read is a rulebook nobody reads.
 */
export default function RulebookPage() {
  return (
    <>
      <h1 className="px-5 sm:px-6">Regelwerk</h1>
      <p className="mb-8 px-5 text-muted-foreground sm:px-6">
        Um ein faires Zusammenspiel auf unserem Server zu garantieren, gibt es
        einige Regeln, an die wir uns halten müssen. Bitte lies dir das
        Regelwerk, vor dem Absenden deines Whitelistantrags, gut durch. Wir
        wünschen dir viel Glück!
      </p>

      <div className="space-y-8 px-5 sm:px-6">
        <section className="border-t pt-8">
          <h2 className="text-lg font-semibold tracking-tight">
            Begrifflichkeiten
          </h2>
          <p className="mt-3 max-w-2xl text-muted-foreground">
            Die Wörter, die in den Regeln vorkommen. Wer die nicht kennt, liest
            die Hälfte davon falsch.
          </p>

          <dl className="mt-6 max-w-3xl space-y-4">
            {GLOSSARY.map((entry) => (
              <div key={entry.term}>
                <dt className="font-medium">{entry.term}</dt>
                <dd className="mt-1 text-sm text-muted-foreground">
                  {entry.meaning}
                </dd>
              </div>
            ))}
          </dl>
        </section>

        <section className="border-t pt-8">
          <h2 className="text-lg font-semibold tracking-tight">Regeln</h2>

          <div className="mt-6 space-y-8">
            {RULEBOOK.map((section) => (
              <div key={section.ref} id={section.ref} className="scroll-mt-24">
                <h3 className="font-semibold tracking-tight">
                  {section.ref} {section.title}
                </h3>
                <ul className="mt-3 max-w-3xl space-y-2.5">
                  {section.items.map((item) => (
                    <li key={item} className="flex gap-3 text-muted-foreground">
                      <span aria-hidden="true" className="select-none">
                        *
                      </span>
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </section>
      </div>

      <div className="mt-10 flex flex-wrap items-center justify-between gap-4 px-5 sm:px-6">
        <p className="mb-0 text-sm text-muted-foreground">
          Gelesen und verstanden? Die Fragen dazu stellst du beim Bewerbungsformular.
        </p>
        <Link className={buttonVariants()} href="/apply">
          Zur Bewerbung
        </Link>
      </div>
    </>
  );
}