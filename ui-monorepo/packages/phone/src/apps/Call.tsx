import * as React from 'react';
import type { LiveCall } from '../contract';

/**
 * The call screen.
 *
 * IT OVERLAYS THE WHOLE PANEL, not a page inside it. A ringing phone that shows
 * you your messages underneath is a phone you can ignore; the state is the
 * reason the character picked the phone up.
 *
 * WHY IT SAYS SO WHEN THERE IS NO VOICE
 *
 * ADR-0020 puts calls on temporary Teamspeak channels, and the server has no
 * query credentials for that yet. The transport refuses cleanly and the call row
 * carries `hasVoice = false`. Hiding that would be worse than the missing voice:
 * a player would hold a phone to their ear in silence and conclude the game is
 * broken, rather than that the feature is not finished.
 */
export function CallScreen({
  call,
  onAnswer,
  onDecline,
  onEnd,
}: {
  call: LiveCall;
  onAnswer: () => void;
  onDecline: () => void;
  onEnd: () => void;
}) {
  const [seconds, setSeconds] = React.useState(0);

  // The timer runs only while there is something to time. An outgoing call that
  // is never answered would otherwise count up from zero and read as a call in
  // progress.
  const timing = call.state === 'active';

  React.useEffect(() => {
    if (!timing) {
      setSeconds(0);
      return undefined;
    }
    const id = window.setInterval(() => setSeconds((s) => s + 1), 1000);
    return () => window.clearInterval(id);
  }, [timing]);

  const mm = String(Math.floor(seconds / 60)).padStart(2, '0');
  const ss = String(seconds % 60).padStart(2, '0');

  const headline =
    call.state === 'incoming'
      ? 'Eingehender Anruf'
      : call.state === 'outgoing'
        ? 'Klingelt…'
        : `${mm}:${ss}`;

  return (
    <div className="pointer-events-auto flex h-full w-[340px] flex-col items-center justify-between rounded-[var(--radius-panel)] border-3 border-[var(--color-primary)] bg-[var(--color-background)] px-6 py-10 text-center text-[var(--color-foreground)] shadow-xl">
      <div>
        <p className="text-xs uppercase tracking-[0.18em] text-[var(--color-muted-foreground)]">
          {headline}
        </p>
        <p className="mt-4 text-2xl font-extrabold tracking-tight">{call.with.name}</p>
        <p className="mt-1 font-mono text-sm text-[var(--color-muted-foreground)]">
          {call.with.number}
        </p>
      </div>

      {!call.hasVoice ? (
        <p className="max-w-[240px] text-xs leading-relaxed text-[var(--color-muted-foreground)]">
          Kein Sprachkanal. Anrufe laufen laut ADR-0020 über temporäre Teamspeak-Kanäle;
          die Anbindung ist noch nicht konfiguriert.
        </p>
      ) : null}

      <div className="flex w-full flex-col gap-3">
        {call.state === 'incoming' ? (
          <div className="flex justify-center gap-6">
            <button
              type="button"
              onClick={onDecline}
              className="h-16 w-16 rounded-full bg-[var(--color-destructive)] text-sm font-bold text-black"
            >
              Ablehnen
            </button>
            <button
              type="button"
              onClick={onAnswer}
              className="h-16 w-16 rounded-full bg-[var(--color-primary)] text-sm font-bold text-[var(--color-primary-foreground)]"
            >
              Annehmen
            </button>
          </div>
        ) : (
          <button
            type="button"
            onClick={onEnd}
            className="h-16 w-full rounded-[var(--radius-panel)] bg-[var(--color-destructive)] text-sm font-bold text-black"
          >
            {call.state === 'active' ? 'Auflegen' : 'Anruf abbrechen'}
          </button>
        )}
      </div>
    </div>
  );
}