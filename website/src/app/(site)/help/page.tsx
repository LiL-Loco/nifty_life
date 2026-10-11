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
import { buttonVariants } from '@/components/ui';

export const metadata: Metadata = { title: 'Hilfe — Nifty Life 2.0' };

/** The world is open Friday evening to Sunday evening. */
const OPENING_HOURS = 'Freitag 19:00 bis Sonntag 22:00';

interface Topic {
  icon: LucideIcon;
  title: string;
  description: string;
  href: string;
  external?: boolean;
}

/**
 * The category grid.
 *
 * The layout follows shadcnblocks.com/block/help1 — an icon, a title, a short
 * description and a chevron per card — with one deliberate omission: the block
 * prints an article count on every card, and this portal has no articles. A
 * count is the one thing on a help page that cannot be approximated, and a
 * number that was invented to fill the slot would be a lie the moment somebody
 * counted. The space goes to the description instead.
 *
 * The Discord entry reads its href from the environment and is dropped when no
 * invite is configured, the same way the landing page's first button degrades.
 * A help centre whose contact card links nowhere is worse than one with six.
 */
const TOPICS: Topic[] = [
  {
    icon: ClipboardList,
    title: 'Bewerbung',
    description: 'Was fehlt noch, bevor du dich bewerben kannst — und was danach passiert.',
    href: '/apply',
  },
  {
    icon: Scale,
    title: 'Regelwerk',
    description: 'Zwölf Abschnitte. Der Text, gegen das Verstöße gemessen werden.',
    href: RULEBOOK_URL,
    external: true,
  },
  {
    icon: UserRound,
    title: 'Charakter',
    description: 'Ein Charakter pro Person. Das Aussehen wird im Spiel eingestellt.',
    href: '/apply/character',
  },
  {
    icon: Hash,
    title: 'Discord',
    description: 'Rollen, Kanäle und der Weg von hier dorthin.',
    href: config.discordInvite,
    external: true,
  },
  {
    icon: MessagesSquare,
    title: 'P&R',
    description: 'Beiträge von Charakteren, nicht von Konten. Melden läuft über das Team.',
    href: '/peeper',
  },
  {
    icon: ShieldAlert,
    title: 'Ban & Status',
    description: 'Wo deine Bewerbung steht, und ein aktiver Ban mit Grund und Ablaufdatum.',
    href: '/status',
  },
  {
    icon: UserRound,
    title: 'Konto',
    description: 'Adresse bestätigen, Discord verknüpfen, Charakter verwalten.',
    href: '/account',
  },
];

/** The short list under the grid: the six places people actually go. */
const SHORTCUTS: { label: string; href: string; external?: boolean }[] = [
  { label: 'Status deiner Bewerbung', href: '/status' },
  { label: 'Portal-Konto anlegen', href: '/register' },
  { label: 'Discord-Konto verknüpfen', href: '/account' },
  { label: 'Charakter anlegen', href: '/apply/character' },
  { label: 'In P&R schreiben', href: '/peeper/pair' },
  { label: 'Regelwerk lesen', href: RULEBOOK_URL, external: true },
];

/**
 * The help centre.
 *
 * One screen of categories, the handful of links that get clicked most, and a
 * way out to Discord for everything this page cannot answer. That last part is
 * the honest one: a help page that implies it covers everything is lying about
 * its own reach, and the server has always been decided in Discord anyway.
 *
 * No session and no database of its own — but it sits in `(site)`, whose layout
 * reads the account to decide what the navigation shows, so this page is
 * rendered per request like every other page in that group. That is a happy
 * accident worth knowing: the Discord invite is read from the environment at
 * REQUEST time here, so changing it and restarting the container is enough.
 * The landing page is prerendered and carries its invite baked in from the
 * build instead, which means the two disagree until that one is rebuilt.
 */
export default function HelpPage() {
  const invite = config.discordInvite;
  const topics = TOPICS.filter((topic) => topic.href !== '');

  return (
    <>
      <h1 className="px-5 sm:px-6">Hilfe</h1>
      <p className="mb-8 px-5 text-muted-foreground sm:px-6">
        Die meisten Fragen beantworten sich schon hier. Der Rest gehört in den
        Discord.
      </p>

      <div className="grid gap-4 px-5 sm:grid-cols-2 sm:px-6 lg:grid-cols-3">
        {topics.map((topic) => {
          const Icon = topic.icon;
          const body = (
            <>
              <Icon
                className="mt-0.5 size-5 shrink-0 text-muted-foreground"
                aria-hidden="true"
              />
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between gap-2">
                  <h2 className="font-semibold tracking-tight">{topic.title}</h2>
                  <ChevronRight
                    className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5"
                    aria-hidden="true"
                  />
                </div>
                <p className="mt-1.5 text-sm text-muted-foreground">
                  {topic.description}
                </p>
              </div>
            </>
          );

          const className =
            'group flex items-start gap-4 rounded-xl border bg-card p-6 transition-colors hover:bg-muted/50';

          return topic.external ? (
            <a
              key={topic.title}
              className={`${className} no-underline`}
              href={topic.href}
              target="_blank"
              rel="noopener noreferrer"
            >
              {body}
            </a>
          ) : (
            <Link key={topic.title} className={className} href={topic.href}>
              {body}
            </Link>
          );
        })}
      </div>

      <div className="mx-5 mt-10 rounded-xl bg-muted/40 px-6 py-6 sm:mx-6">
        <h2 className="text-sm font-semibold tracking-tight">Häufig gesucht</h2>
        <ul className="mt-4 grid gap-x-8 gap-y-2.5 sm:grid-cols-2 lg:grid-cols-3">
          {SHORTCUTS.map((item) => (
            <li key={item.label}>
              {item.external ? (
                <a
                  className="text-sm text-muted-foreground transition-colors hover:text-foreground"
                  href={item.href}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {item.label}
                </a>
              ) : (
                <Link
                  className="text-sm text-muted-foreground transition-colors hover:text-foreground"
                  href={item.href}
                >
                  {item.label}
                </Link>
              )}
            </li>
          ))}
        </ul>

        <p className="mb-0 mt-5 border-t pt-4 text-sm text-muted-foreground">
          Die Welt ist {OPENING_HOURS} offen. In der Zwischenzeit geht nichts
          verloren — was du schreibst, wartet auf dich.
        </p>
      </div>

      <div className="mt-10 flex justify-center px-5 sm:px-6">
        {invite ? (
          <a
            className={buttonVariants()}
            href={invite}
            target="_blank"
            rel="noopener noreferrer"
          >
            Nichts gefunden? Frag im Discord
          </a>
        ) : (
          // No invite configured. Disabled rather than removed, because a help
          // page whose last line is missing reads like an oversight.
          <span className={`${buttonVariants()} pointer-events-none opacity-50`}>
            Nichts gefunden? Einladung folgt
          </span>
        )}
      </div>
    </>
  );
}