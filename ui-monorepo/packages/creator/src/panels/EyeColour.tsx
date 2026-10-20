import * as React from 'react';
import { Caption, List, send } from './creatorTypes';

/**
 * Augenfarbe — the eye-colour stepper.
 *
 * Two strings are on the wire and only two: the section heading and the row
 * label, both 'Augenfarbe', exactly as the vanilla panel wrote them. There is
 * no invented sentence in this file, so there is nothing here to mistranslate.
 *
 * THE NINE OF THIRTY-TWO ARE A PRODUCT DECISION, NOT A BUG LEFT OVER
 *
 * `Labels.EYE_COLOURS` (cl_labels.lua:139) is the engine's own order — 32
 * entries, and everything from index 9 on is one of the joke colours the game
 * unlocks through story missions ('Tequila Sonnenaufgang', 'Besessen',
 * 'Zombie'). The old panel showed `.slice(0, 9)` and the heritage category
 * called it '9 realistische Farben'. That slice is kept here, on purpose and
 * with the same cut, because a character creator that hands every player a
 * zombie eye colour is a different product from the one this server ships.
 *
 * WHAT MOVED FROM A CLOSURE INTO PROPS
 *
 * The old `list()` kept `cur` in its own closure and wrote the new label
 * immediately on click, so two copies of the value existed: the closure's and
 * `state.face.eyeColour`. The shared `List` keeps the optimistic click (two
 * quick clicks must not collapse into one) but re-syncs whenever the index
 * changes from outside, which is what `randomise` and `reset` do — and
 * `setEyeColour` calls `sendRefresh()` (cl_nui.lua:352), so Lua's value is the
 * one that wins on the next echo.
 */

export interface EyeColourProps {
  /** `state.face.eyeColour` — the ENGINE index into EYE_COLOURS, 0..31. */
  eyeColour?: number | null;
  /** `state.labels.EYE_COLOURS`. Only the first nine entries are on show. */
  eyeColourLabels?: readonly string[] | null;
}

/** How many of the engine's 32 colours the creator offers. */
const EYE_COLOUR_COUNT = 9;

/** Module-level, so a missing payload does not re-slice on every render. */
const NO_LABELS: readonly string[] = [];

export function EyeColour({
  eyeColour = 0,
  eyeColourLabels,
}: EyeColourProps) {
  const all = eyeColourLabels == null ? NO_LABELS : eyeColourLabels;
  const eyes = React.useMemo(() => all.slice(0, EYE_COLOUR_COUNT), [all]);

  // The old panel clamped the top only: `Math.min(state.face.eyeColour || 0,
  // eyes.length - 1)`. With no labels that is `Math.min(0, -1)` = -1, which
  // disables BOTH arrows of the stepper on its own — the empty case needs no
  // branch of its own.
  const cur = Math.min(eyeColour || 0, eyes.length - 1);

  const onChange = React.useCallback(
    (index: number) => {
      // Belt to `List`'s braces: with no labels there is no index 0 to send.
      if (eyes.length === 0) return;
      void send('setEyeColour', { index });
    },
    [eyes.length],
  );

  return (
    <>
      <Caption>Augenfarbe</Caption>
      <List label="Augenfarbe" items={eyes} index={cur} onChange={onChange} />
    </>
  );
}