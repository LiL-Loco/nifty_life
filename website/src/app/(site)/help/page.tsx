import type { Metadata } from 'next';
import Link from 'next/link';
import {
  ChevronRight,
  ClipboardList,
  Hash,
  MessagesSquare,
  Scale,
  ShieldAlert,
  UserRound,
  type LucideIcon,
} from 'lucide-react';

import { RULEBOOK_URL } from '@/lib/rulebook';
import { config } from '@/lib/config';

export const metadata: Metadata = { title: 'Hilfe — Nifty Life 2.0' };

/** The world is open Friday evening to Sunday evening. */
const OPENING_HOURS = 'Freitag 19:00 bis Sonntag 22:00';

/** 20 questions, one of which is the rulebook. Both numbers are load-bearing. */
const ANSWER_COUNT = 20;

interface Link_ {
  label: string;
  href: string;
  external?: boolean;
  /** The destination is behind the login. Say so instead of implying otherwise. */
  needsAccount?: boolean;
}

interface Article {
  id: string;
  icon: LucideIcon;
  title: string;
  summary: string;
  paragraphs: string[];
  links: Link_[];
}

/**
 * The help centre.
 *
 * Everything here is readable without an account, and that is the whole point:
 * a stranger reading this at one in the morning is exactly the person the page
 * is for. Only the ACTIONS a page offers need a login, so the answers live here
 * and the links are labelled when they ask for one. The category grid is an
 * index into these articles, not a row of doors into the portal.
 *
 * The grid follows shadcnblocks.com/block/help1, with one deliberate omission:
 * the block prints an article count on every card. There are no articles to
 * count beyond the ones below, so the slot goes to the summary instead — a
 * number invented to fill it would be wrong the moment anybody counted.
 *
 * The Discord article is dropped when no invite is configured, the same way the
 * landing page's first button degrades.
 */
const ARTICLES: Article[] = [
  {
    id: 'bewerbung',
    icon: ClipboardList,
    title: 'Bewerbung',
    summary: 'Was fehlt noch, bevor du abschickst — und was danach passiert.',
    paragraphs: [
      `Bevor du abschickst, brauchst du drei Dinge: ein Portal-Konto, eine bestätigte E-Mail-Adresse und ein verknüpftes Discord-Konto. Fehlt eines davon, lässt sich das Formular nicht absenden.`,
      `Das Formular hat ${ANSWER_COUNT} Fragen. Eine davon ist das Regelwerk, der Rest fragt nach dir und deinem Charakter. Du kannst nur einmal einreichen, und die Entscheidung ist endgültig.`,
      `Eingereicht wird nicht hier entschieden. Die Bewerbung geht nach Discord und wird von einem Menschen gelesen. Deinen Stand siehst du jederzeit auf der Statusseite.`,
    ],
    links: [{ label: 'Statusseite ansehen', href: '/status', needsAccount: true }],
  },
  {
    id: 'regelwerk',
    icon: Scale,
    title: 'Regelwerk',
    summary: 'Zwölf Abschnitte, und warum genau dieser Text gilt.',
    paragraphs: [
      'Das Regelwerk hat zwölf Abschnitte und liegt als Google Doc. Was dort steht, gilt genau so.',
      'Es gibt bewusst keine Kopie hier im Portal. Eine zweite Fassung hier würde irgendwann anders lauten als das Original — und dann hätte niemand mehr eine Stelle, an der man nachsehen kann, was tatsächlich gilt. Im Zweifel gilt das Dokument.',
    ],
    links: [{ label: 'Regelwerk öffnen', href: RULEBOOK_URL, external: true }],
  },
  {
    id: 'charakter',
    icon: UserRound,
    title: 'Charakter',
    summary: 'Ein Charakter pro Person, und was schon im Spiel gilt.',
    paragraphs: [
      'Ein Charakter pro Person. Mehrere Figuren auf einem Account gibt es nicht.',
      'Den Charakter legst du an, wenn deine Bewerbung angenommen wurde. Vorname ist Pflicht, der Rest lässt sich später ändern.',
      'Das Aussehen wird ausschließlich im Spiel eingestellt, nicht über das Portal. Was du hier einträgst, ist der bürgerliche Teil.',
    ],
    links: [{ label: 'Charakter anlegen', href: '/apply/character', needsAccount: true }],
  },
  {
    id: 'discord',
    icon: Hash,
    title: 'Discord',
    summary: 'Rollen, Kanäle und der Weg von hier dorthin.',
    paragraphs: [
      'Discord ist der Ort, an dem entschieden wird — über Bewerbungen, Bans und alles, was sich in einem Ticket nicht klären lässt. Das Portal zeigt nur den Stand.',
      'Teamrollen spiegelt ein Bot aus deinen Discord-Rollen. Wir vergeben sie nicht von Hand, also hilft eine direkte Ansprache im Zweifel nicht schneller.',
      'Charakter-Verknüpfungen und die Codes fürs P&R laufen ebenfalls über Discord.',
    ],
    links: [{ label: 'Discord beitreten', href: config.discordInvite, external: true }],
  },
  {
    id: 'pnr',
    icon: MessagesSquare,
    title: 'P&R',
    summary: 'Was dort steht, wer es schreibt und wie gemeldet wird.',
    paragraphs: [
      'Das P&R ist der interne Feed. Beiträge hängen an einem Charakter, nicht an einem Konto — dieselbe Person im Spiel und hier, dieselbe Moderation auf beiden Seiten.',
      'Schreiben kann, wer im Discord einen Charakter verknüpft hat. Der Code dafür läuft nach 15 Minuten ab.',
      'Das Team meldet, löscht und pinnt. Inhaltlich gilt derselbe Maßstab wie im Spiel: RP, keine Beleidigungen, keine Metadiskussion.',
    ],
    links: [
      { label: 'P&R öffnen', href: '/peeper', needsAccount: true },
      { label: 'Code zum Verknüpfen', href: '/peeper/pair', needsAccount: true },
    ],
  },
  {
    id: 'ban',
    icon: ShieldAlert,
    title: 'Ban & Status',
    summary: 'Wo deine Bewerbung steht, und was ein Ban bedeutet.',
    paragraphs: [
      'Deine Statusseite zeigt genau eine Zeile: eingegangen, freigegeben oder abgelehnt. Steht dort ein aktiver Ban, findest du Grund und Ablaufdatum.',
      'Freigeben und Ablehnen passieren in Discord, nicht im Portal. Hier kann das niemand entscheiden — auch das Team nicht.',
    ],
    links: [{ label: 'Statusseite ansehen', href: '/status', needsAccount: true }],
  },
  {
    id: 'konto',
    icon: UserRound,
    title: 'Konto',
    summary: 'Adresse bestätigen, Discord verknüpfen, Charakter verwalten.',
    paragraphs: [
      'Ein Konto ist eine E-Mail-Adresse und ein Passwort. Das Passwort braucht mindestens zehn Zeichen.',
      'Der Bestätigungslink gilt 24 Stunden und ist einmal nutzbar. Danach kannst du dir einen neuen holen.',
      'Discord verknüpfst du in den Kontoeinstellungen. Ohne Verknüpfung kannst du dich nicht bewerben, aber Konto und Regelwerk bleiben trotzdem erreichbar.',
    ],
    links: [
      { label: 'Kontoeinstellungen', href: '/account', needsAccount: true },
      { label: 'Konto anlegen', href: '/register' },
    ],
  },
];

export default function HelpPage() {
  const invite = config.discordInvite;
  const articles = ARTICLES.filter((article) => article.id !== 'discord' || invite);

  return (
    <>
      <h1 className="px-5 sm:px-6">Hilfe</h1>
      <p className="mb-8 px-5 text-muted-foreground sm:px-6">
        Alles hier steht ohne Konto offen. Nur das, was du danach tun musst,
        verlangt eine Anmeldung.
      </p>

      <div className="grid gap-4 px-5 sm:grid-cols-2 sm:px-6 lg:grid-cols-3">
        {articles.map((article) => {
          const Icon = article.icon;
          return (
            <a
              key={article.id}
              className="group flex items-start gap-4 rounded-xl border bg-card p-6 no-underline transition-colors hover:bg-muted/50"
              href={`#${article.id}`}
            >
              <Icon
                className="mt-0.5 size-5 shrink-0 text-muted-foreground"
                aria-hidden="true"
              />
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between gap-2">
                  <h2 className="font-semibold tracking-tight">{article.title}</h2>
                  <ChevronRight
                    className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5"
                    aria-hidden="true"
                  />
                </div>
                <p className="mt-1.5 text-sm text-muted-foreground">
                  {article.summary}
                </p>
              </div>
            </a>
          );
        })}
      </div>

      <div className="mt-10 space-y-8 px-5 sm:px-6">
        {articles.map((article) => {
          const Icon = article.icon;
          return (
            <section
              key={article.id}
              id={article.id}
              className="scroll-mt-24 border-t pt-8"
            >
              <div className="flex items-center gap-3">
                <Icon className="size-5 text-muted-foreground" aria-hidden="true" />
                <h2 className="text-lg font-semibold tracking-tight">
                  {article.title}
                </h2>
              </div>

              {article.paragraphs.map((paragraph) => (
                <p key={paragraph} className="mt-3 max-w-2xl text-muted-foreground">
                  {paragraph}
                </p>
              ))}

              {article.links.length > 0 && (
                <ul className="mt-4 flex flex-wrap gap-x-6 gap-y-2">
                  {article.links.map((link) => {
                    const suffix = link.needsAccount ? ' (braucht dein Konto)' : '';
                    const inner = (
                      <>
                        {link.label}
                        {suffix && (
                          <span className="text-muted-foreground">{suffix}</span>
                        )}
                      </>
                    );
                    const className =
                      'text-sm underline-offset-4 transition-colors hover:text-foreground hover:underline';

                    return (
                      <li key={link.label}>
                        {link.external ? (
                          <a
                            className={className}
                            href={link.href}
                            target="_blank"
                            rel="noopener noreferrer"
                          >
                            {inner}
                          </a>
                        ) : (
                          <Link className={className} href={link.href}>
                            {inner}
                          </Link>
                        )}
                      </li>
                    );
                  })}
                </ul>
              )}
            </section>
          );
        })}
      </div>

      <div className="mx-5 mt-10 rounded-xl bg-muted/40 px-6 py-6 sm:mx-6">
        <h2 className="text-sm font-semibold tracking-tight">Häufig gesucht</h2>
        <ul className="mt-4 grid gap-x-8 gap-y-2.5 sm:grid-cols-2 lg:grid-cols-3">
          <li>
            <Link className="text-sm text-muted-foreground transition-colors hover:text-foreground" href="/status">
              Status deiner Bewerbung
            </Link>
          </li>
          <li>
            <Link className="text-sm text-muted-foreground transition-colors hover:text-foreground" href="/register">
              Portal-Konto anlegen
            </Link>
          </li>
          <li>
            <Link className="text-sm text-muted-foreground transition-colors hover:text-foreground" href="/peeper/pair">
              In P&R schreiben
            </Link>
          </li>
          <li>
            <a
              className="text-sm text-muted-foreground transition-colors hover:text-foreground"
              href={RULEBOOK_URL}
              target="_blank"
              rel="noopener noreferrer"
            >
              Regelwerk lesen
            </a>
          </li>
        </ul>

        <p className="mb-0 mt-5 border-t pt-4 text-sm text-muted-foreground">
          Die Welt ist {OPENING_HOURS} offen. In der Zwischenzeit geht nichts
          verloren — was du schreibst, wartet auf dich.
        </p>
      </div>

      <div className="mt-10 flex justify-center px-5 sm:px-6">
        {invite ? (
          <a
            className="inline-flex shrink-0 items-center justify-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-medium whitespace-nowrap text-primary-foreground transition-all hover:bg-primary/90"
            href={invite}
            target="_blank"
            rel="noopener noreferrer"
          >
            Nichts gefunden? Frag im Discord
          </a>
        ) : (
          <span className="pointer-events-none inline-flex shrink-0 items-center justify-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-medium whitespace-nowrap text-primary-foreground opacity-50">
            Nichts gefunden? Einladung folgt
          </span>
        )}
      </div>
    </>
  );
}