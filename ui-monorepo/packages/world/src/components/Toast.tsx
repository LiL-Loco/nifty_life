import { cn } from '@nifty/ui';

/**
 * The short-lived confirmation for the last action.
 *
 * It is a confirmation, not a channel: it never claims to be current state and
 * it disappears on its own. `pointer-events-none` because a toast that covers
 * the bottom of the screen must not eat the click that dismisses the panel.
 */
export function Toast({ ok, text }: { ok: boolean; text: string }) {
  return (
    <div
      className={cn(
        'pointer-events-none fixed bottom-[84px] left-1/2 z-[60] -translate-x-1/2 rounded-[2px] border border-[rgba(255,255,255,0.12)] bg-[rgba(18,18,20,0.92)] px-5 py-2.5 text-sm text-[#f2f2f0]',
        !ok && 'border-[var(--color-destructive)]',
      )}
    >
      {text}
    </div>
  );
}