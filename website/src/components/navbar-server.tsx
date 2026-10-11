import Link from 'next/link';

import { cn } from '@/lib/utils';
import { buttonVariants } from '@/components/ui';
import { MobileMenu } from '@/components/navbar';
import { UserMenu } from '@/components/user-menu';
import { config } from '@/lib/config';
import { discordAvatarUrl } from '@/lib/discord';
import type { Account } from '@/lib/auth';

interface NavItem {
  href: string;
  label: string;
  external?: boolean;
}

interface AccountChip {
  avatarUrl: string | null;
  displayName: string;
  subline: string | null;
}

/**
 * The portal's top navigation.
 *
 * Pattern: shadcnblocks.com/navbar35. Three slots on desktop — logo on the
 * left, links centred, account on the right — and a slide-in Sheet on
 * mobile. The links are role-aware: a moderator never sees "Bewerbung" and
 * a stranger never sees "Team". The account slot becomes the user's Discord
 * identity (avatar + username) as soon as the account has one attached, and
 * falls back to the email otherwise.
 *
 * The component is a Server Component (the role decision reads the
 * account from the cookie). The mobile menu and the user dropdown are
 * sibling Client Components because Sheet and DropdownMenu need hooks; the
 * desktop nav stays pure HTML.
 */
export function Navbar({ account }: { account: Account | null }) {
  const items = buildItems(account);
  const chip = buildChip(account);
  const isSignedIn = account !== null;
  const authHref = isSignedIn ? '/account' : '/login';
  const authLabel = isSignedIn
    ? chip?.displayName ?? account!.user.email
    : 'Anmelden';

  return (
    <header className="sticky top-0 z-40 w-full border-b border-border bg-background/80 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="mx-auto flex h-14 max-w-shell items-center gap-4 px-4 sm:px-6">
        {/* Logo */}
        <Link
          href="/"
          className="font-semibold tracking-tight text-foreground no-underline"
        >
          Nifty Life <span className="font-normal text-muted-foreground">2.0</span>
        </Link>

        {/* Desktop links — centred on lg, omitted on smaller viewports. */}
        <nav className="hidden flex-1 items-center justify-center gap-6 text-sm md:flex">
          {items.map((item) =>
            item.external ? (
              <a
                key={item.href}
                href={item.href}
                target="_blank"
                rel="noopener noreferrer"
                className="text-muted-foreground transition-colors hover:text-foreground"
              >
                {item.label}
              </a>
            ) : (
              <Link
                key={item.href}
                href={item.href}
                className="text-muted-foreground transition-colors hover:text-foreground"
              >
                {item.label}
              </Link>
            ),
          )}
        </nav>

        {/* Right slot — the user menu (or the Anmelden button for anonymous). */}
        <div className="ml-auto flex items-center gap-2 md:ml-0">
          {chip ? (
            <UserMenu chip={chip} />
          ) : (
            <Link
              href={authHref}
              className={cn(
                buttonVariants({ size: 'sm' }),
                'hidden md:inline-flex',
              )}
            >
              {authLabel}
            </Link>
          )}

          {/* Mobile hamburger — Sheet trigger. */}
          <MobileMenu
            items={items}
            chip={chip}
            authLabel={authLabel}
            authHref={authHref}
          />
        </div>
      </div>
    </header>
  );
}

function buildItems(account: Account | null): NavItem[] {
  if (account?.isStaff) {
    return [
      { href: '/admin', label: 'Bewerbungen' },
      { href: '/admin/users', label: 'Registrierungen' },
      { href: '/peeper', label: 'P&R' },
    ];
  }
  const items: NavItem[] = [
    { href: '/apply', label: 'Bewerbung' },
    { href: '/status', label: 'Status' },
    { href: '/peeper', label: 'P&R' },
  ];
  if (config.discordInvite) {
    items.push({ href: config.discordInvite, label: 'Discord', external: true });
  }
  return items;
}

/**
 * What the right slot of the navbar should show for the current visitor.
 *
 * Priority: portal username (the always-present display name) > Discord
 * username (only when Discord is linked) > email (the last-resort label,
 * used for legacy accounts that registered before the username column
 * existed). The subline always shows the email so a moderator can confirm
 * which portal account they are in without opening /account.
 */
function buildChip(account: Account | null): AccountChip | null {
  if (!account) return null;
  const displayName =
    account.user.username ??
    account.discord?.username ??
    account.user.email;
  return {
    avatarUrl: account.discord ? discordAvatarUrl(account.discord.discordId) : null,
    displayName,
    subline: account.user.email,
  };
}
