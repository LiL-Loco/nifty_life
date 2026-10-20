import * as React from 'react';
import type { PhoneAccount, PhoneCallLogEntry } from '../contract';

/**
 * The home screen: four apps and the recent-calls list.
 *
 * The app grid is the only navigation there is — there are no breadcrumbs and no
 * back arrow. A phone is a grid you leave and come back to, and the button at the
 * bottom of the panel is the way back to it from anywhere.
 */

interface Props {
  account: PhoneAccount;
  unread: number;
  callLog: PhoneCallLogEntry[];
  onOpenApp: (app: 'dialer' | 'contacts' | 'messages') => void;
}

const APPS: { key: 'dialer' | 'contacts' | 'messages'; label: string; glyph: string }[] = [
  { key: 'dialer', label: 'Wählen', glyph: '☎' },
  { key: 'contacts', label: 'Kontakte', glyph: '☰' },
  { key: 'messages', label: 'Nachrichten', glyph: '✉' },
];

/**
 * How a call ended, in one word.
 *
 * `declined` and `missed` are deliberately different rows: one is a decision the
 * other party made, the other is an absence, and a call log that renders them the
 * same way is lying about something social.
 *
 * `outbound` arrives from the server. The panel is not told its own character id,
 * so it cannot work the direction out itself and does not try.
 */
function endLabel(entry: PhoneCallLogEntry): string {
  switch (entry.end_reason) {
    case 'answered':
      return entry.outbound ? 'Ausgehend' : 'Eingehend';
    case 'declined':
      return 'Abgelehnt';
    case 'missed':
      return entry.outbound ? 'Entgangen' : 'Verpasst';
    case 'busy':
      return 'Besetzt';
    case 'cancelled':
      return 'Abgebrochen';
    case 'unavailable':
      return 'Nicht erreichbar';
    default:
      return 'Laufend';
  }
}

export function Home({ account, unread, callLog, onOpenApp }: Props) {
  return (
    <div className="flex h-full flex-col">
      <div className="grid grid-cols-3 gap-2 p-4">
        {APPS.map((app) => (
          <button
            key={app.key}
            type="button"
            onClick={() => onOpenApp(app.key)}
            className="flex flex-col items-center gap-1.5 rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-background)] px-2 py-4 text-[var(--color-foreground)] hover:border-[var(--color-primary)]"
          >
            <span className="text-xl leading-none text-[var(--color-primary)]">{app.glyph}</span>
            <span className="text-xs font-semibold">{app.label}</span>
            {app.key === 'messages' && unread > 0 ? (
              <span className="mt-0.5 min-w-[18px] rounded-full bg-[var(--color-primary)] px-1.5 text-[10px] font-bold text-[var(--color-primary-foreground)]">
                {unread}
              </span>
            ) : null}
          </button>
        ))}
      </div>

      <div className="px-4 pb-2 text-[10px] font-bold uppercase tracking-[0.18em] text-[var(--color-muted-foreground)]">
        Zuletzt
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto px-2 pb-4">
        {callLog.length === 0 ? (
          <p className="px-2 py-6 text-center text-xs text-[var(--color-muted-foreground)]">
            Noch keine Anrufe.
          </p>
        ) : (
          <ul>
            {callLog.map((entry) => (
              <li
                key={entry.id}
                className="flex items-baseline justify-between gap-2 px-2 py-2 text-sm"
              >
                <span className="truncate">
                  {entry.first_name} {entry.last_name}
                </span>
                <span className="shrink-0 text-xs text-[var(--color-muted-foreground)]">
                  {endLabel(entry)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="border-t border-[var(--color-border)] px-4 py-3 text-center">
        <p className="text-xs text-[var(--color-muted-foreground)]">
          {account.firstName} {account.lastName}
        </p>
      </div>
    </div>
  );
}