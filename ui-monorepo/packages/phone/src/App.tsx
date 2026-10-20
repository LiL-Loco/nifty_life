import * as React from 'react';
import {
  EMPTY_ACCOUNT,
  labelOf,
  onCall,
  onClose,
  onContacts,
  onError,
  onOpen,
  onThreads,
  send,
  type IncomingCall,
  type LiveCall,
  type PhoneCallLogEntry,
  type PhoneContact,
  type PhoneOpenPayload,
  type PhoneThread,
} from './contract';
import { Home } from './apps/Home';
import { Dialer } from './apps/Dialer';
import { Contacts } from './apps/Contacts';
import { Messages } from './apps/Messages';
import { CallScreen } from './apps/Call';

/**
 * The phone.
 *
 * PRESENTATION ONLY, the same rule every other panel here is written under: this
 * file draws what the server sent and forwards what the player did. It never
 * decides whether a number exists, whether a message may be sent, or whether a
 * call can be placed — every button sends a code and the server answers with what
 * actually happened.
 *
 * WHY THE PANEL IS INVISIBLE UNTIL `phone:open`
 *
 * A phone is a thing a character HOLDS. It has no permanent surface: there is no
 * HUD, no icon in the corner, no badge that survives the panel closing. The
 * unread count is server-side and comes with the open payload, so the moment the
 * panel closes the badge goes with it — which is the honest representation of a
 * device in a pocket.
 *
 * That also means this component returns null until the first open, so a CEF
 * that is loaded but idle draws absolutely nothing rather than an empty frame
 * over the game.
 */

type AppName = 'home' | 'dialer' | 'contacts' | 'messages';

export function App() {
  const [open, setOpen] = React.useState(false);
  const [account, setAccount] = React.useState(EMPTY_ACCOUNT);
  const [contacts, setContacts] = React.useState<PhoneContact[]>([]);
  const [threads, setThreads] = React.useState<PhoneThread[]>([]);
  const [callLog, setCallLog] = React.useState<PhoneCallLogEntry[]>([]);
  const [call, setCall] = React.useState<LiveCall | null>(null);
  const [limits, setLimits] = React.useState({ MESSAGE_BODY: 1000, ALIAS: 64, THREAD_PAGE: 50 });
  const [app, setApp] = React.useState<AppName>('home');
  const [notice, setNotice] = React.useState<{ text: string; bad: boolean } | null>(null);
  const noticeTimer = React.useRef<number | null>(null);

  /* ---- notices --------------------------------------------------------- */

  const flash = React.useCallback((text: string, bad = false) => {
    if (noticeTimer.current !== null) window.clearTimeout(noticeTimer.current);
    setNotice({ text, bad });
    noticeTimer.current = window.setTimeout(() => {
      noticeTimer.current = null;
      setNotice(null);
    }, 4000);
  }, []);

  React.useEffect(
    () => () => {
      if (noticeTimer.current !== null) window.clearTimeout(noticeTimer.current);
    },
    [],
  );

  /* ---- lua -> panel ---------------------------------------------------- */

  React.useEffect(
    () =>
      onOpen((data: PhoneOpenPayload) => {
        setAccount(data.account);
        setContacts(data.contacts || []);
        setThreads(data.threads || []);
        setCallLog(data.callLog || []);
        setCall(data.call ?? null);
        setLimits(data.limits || limits);
        setOpen(true);
        // Reopening returns to home rather than wherever the panel happened to be
        // when it closed. Landing back in a half-typed message after a call is
        // disorienting, and the alternative — remembering — is state that has to
        // survive a close it should not survive.
        setApp('home');
      }),
    // `limits` is only read as a fallback when the payload has none, and using it
    // as a dependency would re-subscribe on every change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  React.useEffect(
    () =>
      onClose(() => {
        setOpen(false);
        // Everything is dropped rather than kept. A phone that remembers its
        // state across a close would show a stale message list to a player who
        // read new messages in between, and the panel's only source of truth is
        // what the server sends on open.
        setContacts([]);
        setThreads([]);
        setCallLog([]);
        setCall(null);
        setApp('home');
      }),
    [],
  );

  React.useEffect(
    () =>
      onCall(({ call: next }) => {
        // An incoming push carries only what the server knew at the moment it was
        // sent — id, from, name. It is not a full LiveCall, and treating it as
        // one would render a call screen with no peer name.
        if (!next) {
          setCall(null);
          return;
        }
        if ((next as IncomingCall).state === 'active' && call?.id === next.id) {
          setCall((prev) => (prev ? { ...prev, state: 'active' } : prev));
          return;
        }
        if (call?.id === next.id && (next as IncomingCall).state) {
          return;
        }
        setCall({
          id: next.id,
          state: (next as IncomingCall).state ?? 'incoming',
          outbound: !(next as IncomingCall).state,
          with: {
            number: (next as IncomingCall).from ?? '',
            name: (next as IncomingCall).name ?? (next as IncomingCall).peer ?? 'Unbekannt',
          },
          startedAt: new Date().toISOString(),
          hasVoice: false,
        });
      }),
    [call],
  );

  React.useEffect(
    () =>
      onContacts(({ contacts: next }) => {
        setContacts(next || []);
      }),
    [],
  );

  React.useEffect(
    () =>
      onThreads((data) => {
        // The server answers a send by pushing the row it wrote, so a message the
        // player just sent appears immediately instead of waiting for a refetch
        // that may lose a race.
        if (data.sent) void send('phoneGetState', {});
        if (data.read || data.cleared) void send('phoneGetState', {});
        if (data.bump) {
          flash(`Nachricht von ${data.bump.name}`);
          void send('phoneGetState', {});
        }
      }),
    [flash],
  );

  React.useEffect(
    () =>
      onError(({ message }) => {
        flash(message, true);
      }),
    [flash],
  );

  /* ---- Escape closes, and nothing else does ---------------------------- */

  /**
   * The only key this panel owns. An Escape inside a text field belongs to that
   * field — closing the whole phone because someone dismissed a name they were
   * typing is its own bug, and two panels in this repo already document it.
   */
  React.useEffect(() => {
    if (!open) return undefined;

    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;

      const tag = (event.target as HTMLElement | null)?.tagName || '';
      if (['INPUT', 'TEXTAREA', 'SELECT'].includes(tag)) return;

      event.preventDefault();
      void send('phoneClose', {});
    };

    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  /* ---- unread across every thread ------------------------------------- */

  const unread = React.useMemo(
    () => threads.reduce((sum, t) => sum + (t.unread || 0), 0),
    [threads],
  );

  if (!open) return null;

  /* ---- render ---------------------------------------------------------- */

  const view = (() => {
    switch (app) {
      case 'dialer':
        return (
          <Dialer
            contacts={contacts}
            onCall={(number) => void send('phoneCallStart', { number })}
            onMessage={(number) => {
              setApp('messages');
              window.dispatchEvent(new CustomEvent('phone:compose', { detail: number }));
            }}
          />
        );
      case 'contacts':
        return (
          <Contacts
            contacts={contacts}
            onCall={(number) => void send('phoneCallStart', { number })}
            onMessage={(number) => {
              setApp('messages');
              window.dispatchEvent(new CustomEvent('phone:compose', { detail: number }));
            }}
            onRename={(number, alias) => void send('phoneSaveContact', { number, alias })}
            onDelete={(number) => void send('phoneDeleteContact', { number })}
          />
        );
      case 'messages':
        return <Messages threads={threads} limits={limits} />;
      case 'home':
      default:
        return (
          <Home
            account={account}
            unread={unread}
            callLog={callLog}
            onOpenApp={setApp}
          />
        );
    }
  })();

  return (
    <div className="pointer-events-none fixed inset-0 flex justify-end">
      <div className="pointer-events-auto mr-6 flex h-full flex-col items-center pt-6">
        {call ? (
          <CallScreen
            call={call}
            onAnswer={() => void send('phoneCallAnswer', {})}
            onDecline={() => void send('phoneCallDecline', {})}
            onEnd={() => void send('phoneCallEnd', {})}
          />
        ) : (
          <div className="flex h-full w-[340px] flex-col overflow-hidden rounded-[var(--radius-panel)] border-3 border-[var(--color-border)] bg-[var(--color-background)] text-[var(--color-foreground)] shadow-xl">
            {/* The status bar. Signal and battery are drawn, not measured: there
                is no battery in the schema and inventing one would be a claim the
                server does not make. */}
            <div className="flex items-center justify-between border-b border-[var(--color-border)] px-4 py-2 text-xs">
              <span className="font-bold tracking-[0.08em] text-[var(--color-amber)]">
                {account.number || '—'}
              </span>
              <span className="flex items-center gap-1.5 text-[var(--color-muted-foreground)]">
                <span aria-label="Signal">▮▮▮</span>
                <span aria-label="Akku">▰</span>
              </span>
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto">{view}</div>

            {notice ? (
              <div
                className={[
                  'border-t border-[var(--color-border)] px-4 py-2 text-xs',
                  notice.bad
                    ? 'bg-[var(--color-destructive)] text-black'
                    : 'bg-[var(--color-secondary)] text-[var(--color-secondary-foreground)]',
                ].join(' ')}
              >
                {notice.text}
              </div>
            ) : null}

            {/* Home is always reachable. A player who cannot get back to the grid
                has no way to open a different app, which is the failure a modal
                without a dismiss button has. */}
            <button
              type="button"
              onClick={() => setApp('home')}
              className="border-t border-[var(--color-border)] px-4 py-2.5 text-xs font-bold uppercase tracking-[0.14em] text-[var(--color-primary)] hover:bg-[var(--color-accent)]"
            >
              Startbildschirm
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

export { labelOf };