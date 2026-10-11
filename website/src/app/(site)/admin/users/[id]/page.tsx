import Link from 'next/link';
import { notFound } from 'next/navigation';

import { adminQuery } from '@/lib/db';
import { Card } from '@/components/ui';

export const dynamic = 'force-dynamic';

const GENDER_LABELS: Record<'male' | 'female' | 'nonbinary', string> = {
  male: 'männlich',
  female: 'weiblich',
  nonbinary: 'non-binär',
};

/**
 * The admin profile of a portal account.
 *
 * Click target from /admin/users. Pulls from the game database via the admin
 * pool because the website pool does not — and should not — have SELECT on
 * the wallet, vehicle, property, inventory and phone tables.
 *
 * Six sections, one Card each: account (portal + Discord + staff status),
 * application, character (the row from `characters`), wallet, phone, and
 * possessions (vehicles, properties, inventory). Empty sections are omitted
 * rather than rendered as a "no character" card — the silence says the
 * thing is not there, which is what the user actually came to find out.
 */
export default async function AdminUserProfile({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound();

  const account = await loadAccount(id);
  if (!account) notFound();

  const character = account.discordId
    ? await loadCharacter(account.discordId)
    : null;

  return (
    <>
      <h1 className="mb-1 px-5 sm:px-6">
        {account.username ?? account.email}
      </h1>
      <p className="mb-8 px-5 text-sm text-muted-foreground sm:px-6">
        Portal-Konto · ID{' '}
        <span className="font-mono">{account.id.slice(0, 8)}</span>
      </p>

      <h2 className="px-5 text-sm sm:px-6">Konto</h2>
      <Card className="mx-5 mb-6 sm:mx-6">
        <dl className="m-0">
          <Row term="Anzeigename">{account.username ?? '—'}</Row>
          <Row term="E-Mail">
            <span className="font-mono text-sm">{account.email}</span>
          </Row>
          <Row term="Adresse bestätigt">
            {account.emailVerifiedAt ? 'ja' : 'nein'}
          </Row>
          <Row term="Discord">
            {account.discordUsername ? (
              <>
                {account.discordUsername}{' '}
                <span className="font-mono text-xs text-muted-foreground">
                  {account.discordId}
                </span>
              </>
            ) : (
              '—'
            )}
          </Row>
          <Row term="Team-Rolle">{account.isStaff ? 'Staff' : '—'}</Row>
          <Row term="Aktiv">{account.lastLoginAt ?? '—'}</Row>
          <Row term="Registriert">{account.createdAt}</Row>
        </dl>
      </Card>

      <h2 className="px-5 text-sm sm:px-6">Bewerbung</h2>
      <Card className="mx-5 mb-6 sm:mx-6">
        <dl className="m-0">
          <Row term="Status">{account.applicationStatus ?? 'keine'}</Row>
          {account.applicationSubmittedAt ? (
            <Row term="Eingegangen">{account.applicationSubmittedAt}</Row>
          ) : null}
          {account.applicationReviewedAt ? (
            <Row term="Entschieden">{account.applicationReviewedAt}</Row>
          ) : null}
        </dl>
      </Card>

      {character ? (
        <>
          <h2 className="px-5 text-sm sm:px-6">Charakter</h2>
          <Card className="mx-5 mb-6 sm:mx-6">
            <dl className="m-0">
              <Row term="Name">
                {character.firstName}
                {character.lastName ? ` ${character.lastName}` : ''}
              </Row>
              <Row term="Geschlecht">{GENDER_LABELS[character.gender]}</Row>
              <Row term="Geburtsdatum">{character.dateOfBirth}</Row>
              {character.birthplace ? (
                <Row term="Geburtsort">{character.birthplace}</Row>
              ) : null}
              <Row term="Im Spiel seit">{character.createdAt}</Row>
              <Row term="ID">
                <span className="font-mono text-xs text-muted-foreground">
                  {character.id}
                </span>
              </Row>
            </dl>
          </Card>

          <h2 className="px-5 text-sm sm:px-6">Brieftasche</h2>
          <Card className="mx-5 mb-6 sm:mx-6">
            <dl className="m-0">
              <Row term="Bargeld">
                {formatMoney(character.wallet.cash)} $
              </Row>
              <Row term="Bank">
                {formatMoney(character.wallet.bank)} $
              </Row>
            </dl>
          </Card>

          <h2 className="px-5 text-sm sm:px-6">Telefon</h2>
          {character.phone ? (
            <Card className="mx-5 mb-6 sm:mx-6">
              <dl className="m-0">
                <Row term="Nummer">
                  <span className="font-mono">{character.phone.number}</span>
                </Row>
                <Row term="Status">
                  {character.phone.isActive ? 'aktiv' : 'inaktiv'}
                </Row>
              </dl>
            </Card>
          ) : (
            <p className="mb-6 px-5 text-sm text-muted-foreground sm:px-6">
              Keine Telefonnummer zugewiesen.
            </p>
          )}

          <h2 className="px-5 text-sm sm:px-6">Besitz</h2>
          <Card className="mx-5 mb-6 sm:mx-6">
            <Section
              title="Fahrzeuge"
              empty="Keine Fahrzeuge."
              rows={character.vehicles.map((v) => ({
                key: v.id,
                primary: `${v.model}${v.plate ? ` (${v.plate})` : ''}`,
                secondary: `Tank ${v.fuel.toFixed(0)}% · Motor ${v.engineHealth.toFixed(0)}% · Karosserie ${v.bodyHealth.toFixed(0)}%`,
              }))}
            />
            <Section
              title="Häuser & Geschäfte"
              empty="Keine Immobilien."
              rows={character.properties.map((p) => ({
                key: p.id,
                primary: p.name,
                secondary: `${p.district} · ${p.tier} · ${p.kind === 'housing' ? 'Wohnen' : 'Geschäft'}`,
              }))}
            />
            <Section
              title="Inventar"
              empty="Kein Inventar."
              rows={character.inventory.map((i) => ({
                key: i.id,
                primary: `${i.itemCode} × ${i.quantity}`,
                secondary: `Slot ${i.slot}`,
              }))}
            />
          </Card>
        </>
      ) : (
        <p className="mb-6 px-5 text-sm text-muted-foreground sm:px-6">
          Kein Charakter angelegt.
        </p>
      )}
    </>
  );
}

function Row({ term, children }: { term: string; children: React.ReactNode }) {
  return (
    <>
      <dt className="mt-4 text-xs uppercase tracking-[0.06em] text-muted-foreground first:mt-0">
        {term}
      </dt>
      <dd className="mt-1.5 mb-0 text-sm">{children}</dd>
    </>
  );
}

function Section({
  title,
  rows,
  empty,
}: {
  title: string;
  rows: { key: string; primary: string; secondary: string }[];
  empty: string;
}) {
  if (rows.length === 0) {
    return (
      <div className="mt-4 first:mt-0">
        <p className="text-sm font-medium">{title}</p>
        <p className="text-sm text-muted-foreground">{empty}</p>
      </div>
    );
  }
  return (
    <div className="mt-4 first:mt-0">
      <p className="text-sm font-medium">{title}</p>
      <ul className="m-0 list-none p-0">
        {rows.map((row) => (
          <li key={row.key} className="border-t border-border py-2 first:border-t-0">
            <p className="text-sm">{row.primary}</p>
            <p className="text-xs text-muted-foreground">{row.secondary}</p>
          </li>
        ))}
      </ul>
    </div>
  );
}

function formatMoney(value: number): string {
  return value.toLocaleString('de-DE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

interface AccountInfo {
  id: string;
  email: string;
  username: string | null;
  emailVerifiedAt: string | null;
  lastLoginAt: string | null;
  createdAt: string;
  discordId: string | null;
  discordUsername: string | null;
  isStaff: boolean;
  applicationStatus: string | null;
  applicationSubmittedAt: string | null;
  applicationReviewedAt: string | null;
}

async function loadAccount(userId: string): Promise<AccountInfo | null> {
  const rows = await adminQuery<{
    id: string;
    email: string;
    username: string | null;
    email_verified_at: string | null;
    last_login_at: string | null;
    created_at: string;
    discord_id: string | null;
    discord_username: string | null;
    is_staff: number | null;
    application_status: string | null;
    application_submitted_at: string | null;
    application_reviewed_at: string | null;
  }>(
    `SELECT u.id, u.email, u.username, u.email_verified_at, u.last_login_at, u.created_at,
            d.discord_id, d.username         AS discord_username,
            s.role_id IS NOT NULL          AS is_staff,
            a.status                        AS application_status,
            a.submitted_at                  AS application_submitted_at,
            a.reviewed_at                   AS application_reviewed_at
       FROM portal_users u
       LEFT JOIN portal_user_discord d ON d.user_id = u.id
       LEFT JOIN staff s                ON s.discord_id = d.discord_id
       LEFT JOIN applications a         ON a.user_id = u.id
      WHERE u.id = ?
      LIMIT 1`,
    [userId],
  );

  const row = rows[0];
  if (!row) return null;

  return {
    id: row.id,
    email: row.email,
    username: row.username,
    emailVerifiedAt: row.email_verified_at
      ? String(row.email_verified_at).slice(0, 16).replace('T', ' ')
      : null,
    lastLoginAt: row.last_login_at ? String(row.last_login_at).slice(0, 16).replace('T', ' ') : null,
    createdAt: String(row.created_at).slice(0, 16).replace('T', ' '),
    discordId: row.discord_id,
    discordUsername: row.discord_username,
    isStaff: row.is_staff !== null,
    applicationStatus: row.application_status,
    applicationSubmittedAt: row.application_submitted_at
      ? String(row.application_submitted_at).slice(0, 16).replace('T', ' ')
      : null,
    applicationReviewedAt: row.application_reviewed_at
      ? String(row.application_reviewed_at).slice(0, 16).replace('T', ' ')
      : null,
  };
}

interface CharacterInfo {
  id: string;
  firstName: string;
  lastName: string | null;
  gender: 'male' | 'female' | 'nonbinary';
  dateOfBirth: string;
  birthplace: string | null;
  createdAt: string;
  wallet: { cash: number; bank: number };
  phone: { number: string; isActive: boolean } | null;
  vehicles: { id: string; model: string; plate: string | null; fuel: number; engineHealth: number; bodyHealth: number }[];
  properties: { id: string; name: string; district: string; tier: string; kind: 'housing' | 'business' }[];
  inventory: { id: string; slot: number; itemCode: string; quantity: number }[];
}

async function loadCharacter(discordId: string): Promise<CharacterInfo | null> {
  const charRows = await adminQuery<{
    id: string;
    first_name: string;
    last_name: string | null;
    gender: 'male' | 'female' | 'nonbinary';
    date_of_birth: string;
    birthplace: string | null;
    created_at: string;
  }>(
    `SELECT id, first_name, last_name, gender, date_of_birth, birthplace, created_at
       FROM characters
      WHERE account_id = (SELECT id FROM accounts WHERE discord_id = ? LIMIT 1)
      LIMIT 1`,
    [discordId],
  );
  const row = charRows[0];
  if (!row) return null;

  const walletRows = await adminQuery<{ cash: number; bank: number }>(
    'SELECT cash, bank FROM wallets WHERE character_id = ? LIMIT 1',
    [row.id],
  );
  const phoneRows = await adminQuery<{ number: string; is_active: number }>(
    'SELECT number, is_active FROM phone_accounts WHERE character_id = ? LIMIT 1',
    [row.id],
  );
  const vehicleRows = await adminQuery<{
    id: string;
    model: string;
    plate: string | null;
    fuel: number;
    engine_health: number;
    body_health: number;
  }>(
    `SELECT id, model, plate, fuel, engine_health, body_health
       FROM vehicles
      WHERE owner_id = ?
      ORDER BY created_at DESC`,
    [row.id],
  );
  const propertyRows = await adminQuery<{
    id: string;
    name: string;
    district: string;
    tier: string;
    kind: 'housing' | 'business';
  }>(
    `SELECT p.id, p.name, p.district, p.tier, p.kind
       FROM properties p
       JOIN property_owners o ON o.property_id = p.id
      WHERE o.character_id = ?
      ORDER BY o.acquired_at DESC`,
    [row.id],
  );
  const inventoryRows = await adminQuery<{
    id: string;
    slot: number;
    item_code: string;
    quantity: number;
  }>(
    `SELECT id, slot, item_code, quantity
       FROM inventory_items
      WHERE character_id = ?
      ORDER BY slot ASC`,
    [row.id],
  );

  return {
    id: row.id,
    firstName: row.first_name,
    lastName: row.last_name,
    gender: row.gender,
    dateOfBirth: String(row.date_of_birth).slice(0, 10),
    birthplace: row.birthplace,
    createdAt: String(row.created_at).slice(0, 16).replace('T', ' '),
    wallet: walletRows[0] ?? { cash: 0, bank: 0 },
    phone: phoneRows[0]
      ? { number: phoneRows[0].number, isActive: phoneRows[0].is_active === 1 }
      : null,
    vehicles: vehicleRows.map((v) => ({
      id: v.id,
      model: v.model,
      plate: v.plate,
      fuel: Number(v.fuel),
      engineHealth: Number(v.engine_health),
      bodyHealth: Number(v.body_health),
    })),
    properties: propertyRows.map((p) => ({
      id: p.id,
      name: p.name,
      district: p.district,
      tier: p.tier,
      kind: p.kind,
    })),
    inventory: inventoryRows.map((i) => ({
      id: i.id,
      slot: Number(i.slot),
      itemCode: i.item_code,
      quantity: Number(i.quantity),
    })),
  };
}
