import * as React from 'react';
import { labelOf, type PhoneContact } from '../contract';

/**
 * The contact book.
 *
 * THE ALIAS IS THE OWNER'S, NOT THE CHARACTER'S
 *
 * A contact row is a name ONE player gave ONE other player, and the other side
 * never sees it. That is why the schema stores `alias` per direction and why
 * `labelOf` prefers it: falling back to the character's own name every time
 * would make the alias feature useless, and two players disagreeing about what
 * somebody is called is the normal case rather than the edge one.
 */
export function Contacts({
  contacts,
  onCall,
  onMessage,
  onRename,
  onDelete,
}: {
  contacts: PhoneContact[];
  onCall: (number: string) => void;
  onMessage: (number: string) => void;
  onRename: (number: string, alias: string) => void;
  onDelete: (number: string) => void;
}) {
  const [editing, setEditing] = React.useState<string | null>(null);
  const [draft, setDraft] = React.useState('');
  const [filter, setFilter] = React.useState('');

  const visible = React.useMemo(() => {
    const needle = filter.trim().toLowerCase();
    if (needle === '') return contacts;
    return contacts.filter(
      (c) =>
        labelOf(c).toLowerCase().includes(needle) || c.number.includes(needle),
    );
  }, [contacts, filter]);

  const commit = (number: string) => {
    onRename(number, draft.trim());
    setEditing(null);
    setDraft('');
  };

  return (
    <div className="flex h-full flex-col">
      <div className="border-b border-[var(--color-border)] p-3">
        <input
          type="text"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder="Kontakte durchsuchen"
          autoComplete="off"
          spellCheck={false}
          className="w-full rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm text-[var(--color-foreground)] outline-none placeholder:text-[var(--color-muted-foreground)]"
        />
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto">
        {visible.length === 0 ? (
          <p className="px-4 py-8 text-center text-xs text-[var(--color-muted-foreground)]">
            {contacts.length === 0
              ? 'Noch keine Kontakte. Wähle eine Nummer und speichere sie.'
              : 'Kein Treffer.'}
          </p>
        ) : (
          <ul>
            {visible.map((c) => (
              <li key={c.number} className="border-b border-[var(--color-border)] px-3 py-2.5">
                {editing === c.number ? (
                  <div className="flex gap-1.5">
                    <input
                      type="text"
                      value={draft}
                      autoFocus
                      onChange={(e) => setDraft(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') commit(c.number);
                        if (e.key === 'Escape') setEditing(null);
                      }}
                      placeholder={labelOf(c)}
                      className="min-w-0 flex-1 rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-background)] px-2 py-1 text-sm outline-none"
                    />
                    <button
                      type="button"
                      onClick={() => commit(c.number)}
                      className="rounded-[var(--radius-panel)] bg-[var(--color-primary)] px-3 text-xs font-bold text-[var(--color-primary-foreground)]"
                    >
                      OK
                    </button>
                  </div>
                ) : (
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => onCall(c.number)}
                      className="min-w-0 flex-1 text-left"
                    >
                      <span className="block truncate text-sm font-semibold text-[var(--color-foreground)]">
                        {labelOf(c)}
                      </span>
                      <span className="block font-mono text-xs text-[var(--color-muted-foreground)]">
                        {c.number}
                        {c.is_active === 0 ? ' · gesperrt' : ''}
                      </span>
                    </button>
                    <button
                      type="button"
                      onClick={() => onMessage(c.number)}
                      aria-label="Nachricht"
                      className="h-8 w-8 rounded-[var(--radius-panel)] border border-[var(--color-border)] text-xs hover:border-[var(--color-primary)]"
                    >
                      ✉
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setEditing(c.number);
                        setDraft(c.alias ?? '');
                      }}
                      aria-label="Umbenennen"
                      className="h-8 w-8 rounded-[var(--radius-panel)] border border-[var(--color-border)] text-xs hover:border-[var(--color-primary)]"
                    >
                      ✎
                    </button>
                    <button
                      type="button"
                      onClick={() => onDelete(c.number)}
                      aria-label="Löschen"
                      className="h-8 w-8 rounded-[var(--radius-panel)] border border-[var(--color-border)] text-xs text-[var(--color-destructive)] hover:border-[var(--color-destructive)]"
                    >
                      ×
                    </button>
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}