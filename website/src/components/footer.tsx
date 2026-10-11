import Link from 'next/link';

import { RULEBOOK_URL } from '@/lib/rulebook';
import { config } from '@/lib/config';

/**
 * The portal footer.
 *
 * Layout follows shadcnblocks.com/footer2: a six-column grid on desktop with
 * the logo and tagline in the first two columns, then four link sections.
 * Below `lg` the grid drops to two columns; below `sm` the whole thing
 * stacks.
 *
 * The bottom row is a single line on `sm` and stacks above `sm`: copyright on
 * the left, version on the right. There is no Impressum or Datenschutz page
 * because the project does not have one — the placeholders are not filled
 * in with a "coming soon" link, which would be a lie.
 *
 * The Discord link is conditional: an unconfigured server has no invite, and
 * a footer link to "#" is worse than no link at all.
 */
export function Footer() {
  const year = new Date().getFullYear();
  const discord = config.discordInvite;

  return (
    <footer className="border-t border-border bg-background">
      <div className="mx-auto max-w-shell px-6 py-12">
        <div className="grid gap-8 md:grid-cols-2 md:gap-10 lg:grid-cols-6">
          {/* Logo + tagline. Two columns on lg, full width on smaller. */}
          <div className="md:col-span-2 lg:col-span-2">
            <Link href="/" className="text-base font-semibold tracking-tight text-foreground no-underline">
              Nifty Life <span className="font-normal text-muted-foreground">2.0</span>
            </Link>
            <p className="mt-3 text-sm text-muted-foreground">
              Roleplay-Server fürs Wochenende. Freitag 19:00 bis Sonntag 22:00.
              In der Zwischenzeit geht nichts verloren.
            </p>
          </div>

          {/* Link sections, one per column on lg. */}
          <div>
            <h3 className="text-sm font-semibold tracking-tight text-foreground">
              Spielen
            </h3>
            <ul className="mt-3 space-y-2 text-sm">
              <li>
                <Link
                  href="/apply"
                  className="text-muted-foreground transition-colors hover:text-foreground"
                >
                  Bewerbung
                </Link>
              </li>
              <li>
                <Link
                  href="/status"
                  className="text-muted-foreground transition-colors hover:text-foreground"
                >
                  Status
                </Link>
              </li>
              <li>
                <Link
                  href="/peeper"
                  className="text-muted-foreground transition-colors hover:text-foreground"
                >
                  P&amp;R
                </Link>
              </li>
            </ul>
          </div>

          <div>
            <h3 className="text-sm font-semibold tracking-tight text-foreground">
              Konto
            </h3>
            <ul className="mt-3 space-y-2 text-sm">
              <li>
                <Link
                  href="/login"
                  className="text-muted-foreground transition-colors hover:text-foreground"
                >
                  Anmelden
                </Link>
              </li>
              <li>
                <Link
                  href="/register"
                  className="text-muted-foreground transition-colors hover:text-foreground"
                >
                  Registrieren
                </Link>
              </li>
              <li>
                <Link
                  href="/account"
                  className="text-muted-foreground transition-colors hover:text-foreground"
                >
                  Konto
                </Link>
              </li>
            </ul>
          </div>

          <div>
            <h3 className="text-sm font-semibold tracking-tight text-foreground">
              Community
            </h3>
            <ul className="mt-3 space-y-2 text-sm">
              {discord ? (
                <li>
                  <a
                    href={discord}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-muted-foreground transition-colors hover:text-foreground"
                  >
                    Discord
                  </a>
                </li>
              ) : null}
              <li>
                <a
                  href={RULEBOOK_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-muted-foreground transition-colors hover:text-foreground"
                >
                  Regelwerk
                </a>
              </li>
            </ul>
          </div>

          <div>
            <h3 className="text-sm font-semibold tracking-tight text-foreground">
              Sitzung
            </h3>
            <ul className="mt-3 space-y-2 text-sm">
              <li>
                <Link
                  href="/auth/logout"
                  className="text-muted-foreground transition-colors hover:text-foreground"
                >
                  Abmelden
                </Link>
              </li>
            </ul>
          </div>
        </div>

        <div className="mt-10 flex flex-col-reverse gap-3 border-t border-border pt-6 text-sm text-muted-foreground sm:flex-row sm:items-center sm:justify-between">
          <p className="m-0">
            © {year} Nifty Life. Freizeitprojekt, kein kommerzielles Angebot.
          </p>
          <p className="m-0">
            <span className="text-xs">v2.0</span>
          </p>
        </div>
      </div>
    </footer>
  );
}
