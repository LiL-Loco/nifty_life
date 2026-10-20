import type { JobAssignment, Money } from '../contract';
import { formatMoney } from '../format';

/**
 * The always-on HUD: balances, and the duty chip while a shift is running.
 *
 * `pointer-events-none` is not decoration. This frame is composited over a
 * running game, and the HUD sits in the top-right corner where the minimap is;
 * a box that swallows clicks there is the exact class of bug that made this
 * panel's creator frame cover another resource's panel.
 */
export function Hud({ money, jobs }: { money: Money; jobs: JobAssignment[] }) {
  const onDuty = jobs.find((job) => job.onDuty) ?? null;

  return (
    <div className="pointer-events-none fixed right-[22px] top-[18px] z-[40] flex flex-col items-end gap-2 tabular-nums">
      <div className="flex items-baseline gap-2.5">
        <span className="text-xl font-semibold text-[var(--color-foreground)] [text-shadow:0_1px_3px_rgba(0,0,0,0.85)]">
          {formatMoney(money.cash)}
        </span>
        <span className="text-sm font-normal text-[rgba(242,242,240,0.62)] [text-shadow:0_1px_3px_rgba(0,0,0,0.85)]">
          {formatMoney(money.bank)}
        </span>
      </div>

      {onDuty ? (
        <div className="flex items-center gap-2 rounded-[2px] border border-[rgba(255,255,255,0.1)] bg-[rgba(18,18,20,0.72)] px-2.5 py-1 text-xs uppercase tracking-[0.08em] text-[#e8e8e4]">
          <span className="h-1.5 w-1.5 rounded-full bg-[var(--color-success)]" />
          <span>{onDuty.name}</span>
        </div>
      ) : null}
    </div>
  );
}