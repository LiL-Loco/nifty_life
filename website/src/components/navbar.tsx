'use client';

import Link from 'next/link';
import { Menu } from 'lucide-react';

import { Button } from '@/components/ui/button';
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet';

interface NavItem {
  href: string;
  label: string;
  /** External links (Discord, rulebook) open in a new tab. */
  external?: boolean;
  description?: string;
}

interface AccountChip {
  avatarUrl: string | null;
  displayName: string;
  subline: string | null;
}

/**
 * The mobile menu.
 *
 * Lives in its own Client Component because Sheet is a Radix primitive and
 * needs hooks. The desktop navbar (server-rendered) embeds this for the
 * hamburger trigger, and the sheet body mirrors the desktop nav so a
 * mobile visitor sees the same destinations, just stacked.
 */
export function MobileMenu({
  items,
  chip,
  authLabel,
  authHref,
}: {
  items: NavItem[];
  /** What the bottom CTA should render. Null means "anonymous — show the
   *  Anmelden button". A populated chip means "signed in — show the chip". */
  chip: AccountChip | null;
  authLabel: string;
  authHref: string;
}) {
  return (
    <Sheet>
      <SheetTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          className="md:hidden"
          aria-label="Menü öffnen"
        >
          {chip?.avatarUrl ? (
            <img
              src={chip.avatarUrl}
              alt=""
              width={20}
              height={20}
              className="size-5 rounded-full object-cover"
            />
          ) : (
            <Menu className="size-5" />
          )}
        </Button>
      </SheetTrigger>
      <SheetContent side="right" className="flex w-72 flex-col gap-6 px-6">
        <SheetHeader>
          <SheetTitle>Nifty Life</SheetTitle>
          <SheetDescription>Portal-Navigation</SheetDescription>
        </SheetHeader>

        <nav className="flex flex-col gap-1">
          {items.map((item) => (
            <SheetClose asChild key={item.href}>
              <Link
                href={item.href}
                target={item.external ? '_blank' : undefined}
                rel={item.external ? 'noopener noreferrer' : undefined}
                className="rounded-md px-3 py-2 text-sm text-foreground transition-colors hover:bg-accent"
              >
                {item.label}
              </Link>
            </SheetClose>
          ))}
        </nav>

        <div className="mt-auto border-t border-border pt-4">
          <SheetClose asChild>
            {chip ? (
              <Link
                href={authHref}
                className="flex items-center gap-3 rounded-md px-2 py-2 text-foreground transition-colors hover:bg-accent"
              >
                {chip.avatarUrl ? (
                  <span className="grid size-9 place-items-center overflow-hidden rounded-full bg-muted">
                    <img
                      src={chip.avatarUrl}
                      alt=""
                      width={36}
                      height={36}
                      className="size-full object-cover"
                    />
                  </span>
                ) : (
                  <span className="grid size-9 place-items-center rounded-full bg-muted text-sm text-muted-foreground">
                    {chip.displayName.charAt(0).toUpperCase()}
                  </span>
                )}
                <span className="flex flex-col leading-tight">
                  <span className="text-sm font-medium">{chip.displayName}</span>
                  {chip.subline ? (
                    <span className="text-xs text-muted-foreground">{chip.subline}</span>
                  ) : null}
                </span>
              </Link>
            ) : (
              <Link
                href={authHref}
                className="block w-full rounded-md bg-primary px-3 py-2 text-center text-sm font-medium text-primary-foreground"
              >
                {authLabel}
              </Link>
            )}
          </SheetClose>
        </div>
      </SheetContent>
    </Sheet>
  );
}
