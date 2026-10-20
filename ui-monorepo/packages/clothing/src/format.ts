import type { Kind, Piece } from './contract';

/**
 * Normalise a value that Lua claims is a list.
 *
 * `cl_nui.lua` writes `outfits = list or {}` and `items = data.items or {}`.
 * An EMPTY Lua table has no array-or-object identity, and FiveM's JSON
 * encoder is not consistent about which one it emits — so `data.outfits` can
 * arrive as `[]` or as `{}`. Calling `.map` on the second one is a hard crash
 * on an empty wardrobe, which is exactly the state a fresh character has.
 */
export function asList<T>(value: T[] | Record<string, never> | null | undefined): T[] {
  return Array.isArray(value) ? value : [];
}

/** store.js:17-19 — German thousands separator, at most two decimals. */
export function money(n: number | null | undefined): string {
  return Number(n || 0).toLocaleString('de-DE', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

/**
 * Cache key for one (kind, slot) bucket.
 *
 * Both the `owned` patch map and the store's item cache need the same key, and
 * the two must agree — `owned` arrives with the slot id as an already
 * stringified object key, so it is normalised through here on the way in.
 */
export function slotKey(kind: Kind, id: number): string {
  return `${kind}:${id}`;
}

/**
 * React key for one owned piece.
 *
 * A piece has no id (see contract.ts), so identity is the triple the rows are
 * actually keyed by in SQL: collection + drawable + texture.
 */
export function pieceKey(piece: Piece): string {
  return `${piece.collection}|${piece.drawable}|${piece.texture}`;
}

/** 'Vorname Nachname', trimmed; '' when either part is missing or null. */
export function characterName(
  character: { firstName: string | null; lastName: string | null } | null | undefined,
): string {
  if (!character) return '';
  return [character.firstName, character.lastName]
    .filter((part): part is string => typeof part === 'string' && part.length > 0)
    .join(' ');
}