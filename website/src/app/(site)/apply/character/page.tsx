import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { existingCharacterForDiscord } from '@/lib/characters';
import { CHARACTER_FORM_INTRO } from '@/lib/copy';
import { one } from '@/lib/db';
import { Card } from '@/components/ui';
import { CharacterForm } from './character-form';

export const dynamic = 'force-dynamic';

export const metadata = { title: 'Charakter anlegen — Nifty Life 2.0' };

/**
 * The character creation form.
 *
 * Reachable only after the application has been approved. The gates are run
 * here, not just in the server action, so a visitor who somehow lands here
 * with an outstanding application sees the same "almost there" page they
 * would see on /apply — not a form that will only fail at submit.
 *
 * The fields are exactly the inputs the stored procedure expects (ADR-0008,
 * migration 021). The procedure re-validates them; this layer carries the
 * shape errors the form can produce.
 */
export default async function CharacterPage() {
  const account = await currentAccount();
  if (!account) redirect('/login');

  if (!account.user.emailVerifiedAt) {
    return (
      <Card className="mx-5 sm:mx-6">
        <h1 className="mt-0">E-Mail noch nicht bestätigt</h1>
        <p>
          Ohne bestätigte Adresse lässt sich kein Charakter anlegen. Bestätige
          zuerst den Link in der Mail, die wir dir geschickt haben.
        </p>
      </Card>
    );
  }

  if (!account.discord) {
    return (
      <Card className="mx-5 sm:mx-6">
        <h1 className="mt-0">Discord fehlt noch</h1>
        <p>
          Bevor ein Charakter angelegt werden kann, muss dein Discord-Konto
          verknüpft sein.
        </p>
        <p className="mb-0">
          <a className="underline" href="/account">
            Zum Konto, um Discord zu verknüpfen
          </a>
        </p>
      </Card>
    );
  }

  const approved = account.isStaff || await hasApprovedApplication(account.user.id);
  if (!approved) {
    return (
      <Card className="mx-5 sm:mx-6">
        <h1 className="mt-0">Bewerbung noch nicht freigegeben</h1>
        <p>
          Sobald deine Bewerbung von einem Menschen geprüft und freigegeben
          wurde, kannst du hier deinen Charakter anlegen.
        </p>
        <p className="mb-0">
          <a className="underline" href="/status">
            Status der Bewerbung ansehen
          </a>
        </p>
      </Card>
    );
  }

  const existing = await existingCharacterForDiscord(account.discord.discordId);
  if (existing) {
    redirect('/apply/character/done');
  }

  return (
    <>
      <h1 className="px-5 sm:px-6">Charakter anlegen</h1>
      <p className="mb-8 px-5 text-muted-foreground sm:px-6">
        {CHARACTER_FORM_INTRO}
      </p>
      <CharacterForm />
    </>
  );
}

async function hasApprovedApplication(userId: string): Promise<boolean> {
  const row = await one<{ id: string }>(
    `SELECT id FROM applications WHERE user_id = ? AND status = 'approved' LIMIT 1`,
    [userId],
  );
  return row !== null;
}
