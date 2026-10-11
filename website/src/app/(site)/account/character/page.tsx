import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { existingCharacterForDiscord } from '@/lib/characters';
import { Card } from '@/components/ui';
import { CharacterForm } from '@/app/(site)/apply/character/character-form';

export const metadata = { title: 'Charaktere — Nifty Life 2.0' };

/**
 * The user's character(s).
 *
 * One character per account (ADR-0008). If the account already has one, the
 * page shows it. If not, the creation form is rendered directly on this page
 * — no intermediate "click here to create" — because the user came here to
 * see a character and the natural reaction to "no character yet" is the form
 * to make one.
 *
 * The form has its own gates (email verified, Discord linked, application
 * approved or staff). They fire as server-action errors, not as separate
 * cards here, because the user menu already implies they have the basics
 * sorted (otherwise the form would not be reachable in the first place).
 */
export default async function AccountCharacterPage() {
  const account = await currentAccount();
  if (!account) redirect('/login');
  if (!account.discord) redirect('/account');

  const character = await existingCharacterForDiscord(account.discord.discordId);

  if (character) {
    return (
      <>
        <h1 className="px-5 sm:px-6">Charaktere</h1>
        <p className="mb-8 px-5 text-muted-foreground sm:px-6">
          Pro Konto ist laut Regelwerk genau ein Charakter erlaubt.
        </p>
        <Card className="mx-5 sm:mx-6">
          <dl className="m-0">
            <dt className={term}>Name</dt>
            <dd className={value}>
              {character.firstName}
              {character.lastName ? ` ${character.lastName}` : ''}
            </dd>
            <dt className={term}>Geschlecht</dt>
            <dd className={value}>{GENDER_LABELS[character.gender]}</dd>
            <dt className={term}>Geburtsdatum</dt>
            <dd className={value}>{character.dateOfBirth}</dd>
            {character.birthplace ? (
              <>
                <dt className={term}>Geburtsort</dt>
                <dd className={value}>{character.birthplace}</dd>
              </>
            ) : null}
            <dt className={term}>Im Spiel seit</dt>
            <dd className={value}>
              {String(character.createdAt).slice(0, 16).replace('T', ' ')}
            </dd>
            <dt className={term}>ID</dt>
            <dd className={value}>
              <span className="font-mono text-xs text-muted-foreground">
                {character.characterId}
              </span>
            </dd>
          </dl>
          <p className="mb-0 mt-2 text-sm text-muted-foreground">
            Aussehen und weitere Details werden im Spiel eingestellt. Verbinde
            dich während des Zeitfensters mit dem Server, um sie zu pflegen.
          </p>
        </Card>
      </>
    );
  }

  return (
    <>
      <h1 className="px-5 sm:px-6">Charakter anlegen</h1>
      <p className="mb-8 px-5 text-muted-foreground sm:px-6">
        Vorname, Nachname, Geschlecht und Geburtsdatum. Das Aussehen wird im
        Spiel eingestellt.
      </p>
      <CharacterForm />
    </>
  );
}

const term = 'mt-4 text-xs uppercase tracking-[0.06em] text-muted-foreground';
const value = 'mt-1.5 mb-0';

const GENDER_LABELS: Record<'male' | 'female' | 'nonbinary', string> = {
  male: 'männlich',
  female: 'weiblich',
  nonbinary: 'non-binär',
};
