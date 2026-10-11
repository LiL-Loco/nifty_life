'use client';

import Link from 'next/link';
import { LogOut, Settings, User as UserIcon, Users } from 'lucide-react';

import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';

interface AccountChip {
  avatarUrl: string | null;
  displayName: string;
  subline: string | null;
}

/**
 * The user menu in the navbar.
 *
 * Click on the avatar or username opens a dropdown with the destinations that
 * used to live behind a single link to /account. The trigger is the chip
 * itself, so the user sees the same affordance on desktop and mobile and
 * never has to discover a second button.
 */
export function UserMenu({ chip }: { chip: AccountChip }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          className="hidden h-auto items-center gap-2 rounded-md px-1.5 py-1 text-sm md:inline-flex"
          aria-label="Konto-Menü öffnen"
        >
          {chip.avatarUrl ? (
            <span className="grid size-7 place-items-center overflow-hidden rounded-full bg-muted">
              <img
                src={chip.avatarUrl}
                alt=""
                width={28}
                height={28}
                className="size-full object-cover"
              />
            </span>
          ) : (
            <span className="grid size-7 place-items-center rounded-full bg-muted text-xs text-muted-foreground">
              {chip.displayName.charAt(0).toUpperCase()}
            </span>
          )}
          <span className="flex flex-col leading-tight">
            <span className="font-medium text-foreground">{chip.displayName}</span>
            {chip.subline ? (
              <span className="text-xs text-muted-foreground">{chip.subline}</span>
            ) : null}
          </span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        <DropdownMenuLabel className="font-normal">
          <div className="flex flex-col">
            <span className="font-medium">{chip.displayName}</span>
            {chip.subline ? (
              <span className="text-xs text-muted-foreground">{chip.subline}</span>
            ) : null}
          </div>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem asChild>
          <Link href="/account/profile">
            <UserIcon />
            Profil bearbeiten
          </Link>
        </DropdownMenuItem>
        <DropdownMenuItem asChild>
          <Link href="/account/settings">
            <Settings />
            Einstellungen
          </Link>
        </DropdownMenuItem>
        <DropdownMenuItem asChild>
          <Link href="/account/character">
            <Users />
            Charaktere
          </Link>
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem asChild>
          <Link href="/auth/logout">
            <LogOut />
            Abmelden
          </Link>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
