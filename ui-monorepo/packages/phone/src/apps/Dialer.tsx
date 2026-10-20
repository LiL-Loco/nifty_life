import * as React from 'react';
import { KEYPAD, formatNumber, labelOf, type PhoneContact } from '../contract';

/**
 * The dialer.
 *
 * WHAT THE KEYPAD DOES AND DOES NOT SEND
 *
 * The server owns the number format. `Phone.normalise` strips everything that is
 * not a digit, drops a `0049` or leading zero, and checks the result against
 * `555` plus exactly four digits — so the keypad sends raw digits and lets the
 * server be the only thing that decides what a number IS. A panel-side
 * formatter would be a second spelling of every number, and `uq_phone_accounts_number`
 * is a string comparison: `5551234` and `555-1234` would be two accounts.
 *
 * The preview here is DISPLAY only and goes through `formatNumber`, which is the
 * same spelling the server stores.
 */
export function Dialer({
  contacts,
  onCall,
  onMessage,
}: {
  contacts: PhoneContact[];
  onCall: (number: string) => void;
  onMessage: (number: string) => void;
}) {
  const [digits, setDigits] = React.useState('');

  const press = (d: string) => setDigits((prev) => (prev.length >= 7 ? prev : prev + d));

  const backspace = () => setDigits((prev) => prev.slice(0, -1));

  /** Best-effort name for what is being dialled, from the contact book. */
  const match = React.useMemo(() => {
    if (digits.length < 4) return null;
    const wanted = formatNumber(digits);
    return contacts.find((c) => c.number === wanted) ?? null;
  }, [digits, contacts]);

  // Enter dials, Backspace deletes. Both are here rather than nowhere because a
  // keypad nobody can use without the mouse is a worse phone than the one it
  // replaces — but Escape is deliberately NOT bound: it belongs to the text
  // field in Contacts and Messages, and stealing it here would break both.
  React.useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (/^[0-9*#]$/.test(event.key)) {
        event.preventDefault();
        press(event.key);
      } else if (event.key === 'Backspace') {
        event.preventDefault();
        backspace();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const target = formatNumber(digits);

  return (
    <div className="flex h-full flex-col">
      <div className="px-4 pb-2 pt-5 text-center">
        <p className="font-mono text-3xl font-bold tracking-tight text-[var(--color-foreground)]">
          {target || <span className="text-[var(--color-muted-foreground)]">—</span>}
        </p>
        {match ? (
          <p className="mt-1 text-sm text-[var(--color-primary)]">{labelOf(match)}</p>
        ) : (
          <p className="mt-1 h-5 text-xs text-[var(--color-muted-foreground)]">
            {digits.length >= 7 ? 'Kein Kontakt' : 'Vorwahl 555'}
          </p>
        )}
      </div>

      <div className="grid grid-cols-3 gap-1.5 px-6 py-2">
        {KEYPAD.map((key) => (
          <button
            key={key.digit}
            type="button"
            onClick={() => press(key.digit)}
            className="flex flex-col items-center justify-center rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-background)] py-3 text-[var(--color-foreground)] hover:border-[var(--color-primary)]"
          >
            <span className="text-xl font-bold leading-none">{key.digit}</span>
            <span className="mt-0.5 h-3 text-[9px] tracking-[0.2em] text-[var(--color-muted-foreground)]">
              {key.letters}
            </span>
          </button>
        ))}
      </div>

      <div className="mt-auto flex items-center gap-2 px-6 pb-5 pt-2">
        <button
          type="button"
          onClick={backspace}
          className="h-12 w-14 rounded-[var(--radius-panel)] border border-[var(--color-border)] text-lg text-[var(--color-foreground)] hover:border-[var(--color-primary)]"
          aria-label="Löschen"
        >
          ⌫
        </button>
        <button
          type="button"
          disabled={digits.length < 7}
          onClick={() => onCall(target)}
          className="h-12 flex-1 rounded-[var(--radius-panel)] bg-[var(--color-primary)] text-sm font-bold text-[var(--color-primary-foreground)] disabled:opacity-40"
        >
          Anrufen
        </button>
        <button
          type="button"
          disabled={digits.length < 7}
          onClick={() => onMessage(target)}
          className="h-12 w-14 rounded-[var(--radius-panel)] border border-[var(--color-border)] text-lg text-[var(--color-foreground)] hover:border-[var(--color-primary)] disabled:opacity-40"
          aria-label="Nachricht"
        >
          ✉
        </button>
      </div>
    </div>
  );
}