import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { existingCharacterForDiscord } from '@/lib/characters';
import { buttonVariants } from '@/components/ui';
import { Card } from '@/components/ui/card';

export const metadata = { title: 'Charakter angelegt — Nifty Life 2.0' };

/**
 * Confirmation page after the character has been written.
 *
 * The server action redirects here on success, and the gate is the same as
 * on the form: signed in, Discord linked, application approved, and a
 * character already exists. If any of those is missing the user is sent
 * back to the form; this page is a one-way arrival.
 */
export default async function CharacterDonePage() {
  const account = await currentAccount();
  if (!account) redirect('/login');
  if (!account.discord) redirect('/login');

  const character = await existingCharacterForDiscord(account.discord.discordId);
  if (!character) redirect('/apply/character');

  return (
    <div className="flex min-h-svh w-full items-start justify-center p-6 md:p-10">
      <div className="w-full max-w-md">
        <Card className="mx-5 sm:mx-6">
          <h1 className="mt-0">Charakter angelegt</h1>
          <p>
            <strong>
              {character.firstName}
              {character.lastName ? ` ${character.lastName}` : ''}
            </strong>{' '}
            ist im Spiel registriert. Du kannst dich jetzt während des
            Zeitfensters mit dem Server verbinden und das Aussehen im Charakter-
            Editor fertigstellen.
          </p>
          <p className="mb-0">
            <Link className={buttonVariants()} href="/status">
              Zur Status-Seite
            </Link>
          </p>
        </Card>
      </div>
    </div>
  );
}
