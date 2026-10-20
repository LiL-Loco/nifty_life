/**
 * German number layout.
 *
 * Prices and wages arrive from the server already rounded to two decimals — this
 * only lays them out. It never re-rounds, never re-prices, and never invents a
 * number the server did not send; `undefined` (a job in the assignment list,
 * which carries no wage) lays out as 0,00 exactly as the old panel did.
 */
export function formatMoney(value: number | undefined | null): string {
  return `${Number(value || 0).toLocaleString('de-DE', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })} $`;
}