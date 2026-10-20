import { Caption, Row, type PanelNav } from './creatorTypes';

/**
 * The heritage category menu: two buttons.
 *
 * `renderHeritageCategory` (app.js:648-654) reads ZERO state fields — it is a
 * separator and two rows — so this panel takes no `state` prop at all. That is
 * not an omission: passing state here would invite a future edit to read
 * something the Lua side does not usefully send.
 *
 * Both targets are one push deep. `parents` is this group's other panel;
 * `eyeColour` belongs to the heritage-adjacent group and slices
 * `labels.EYE_COLOURS` to `.slice(0, 9)` — the other 23 engine eye colours are
 * unreachable by design.
 *
 * No Lua call happens here: a category button is pure navigation.
 */

export interface HeritageProps {
  nav: PanelNav;
}

export function Heritage({ nav }: HeritageProps) {
  return (
    <div className="flex flex-col gap-1.5">
      <Caption>Kategorien</Caption>
      <Row
        label="Eltern"
        desc="Vater, Mutter und Mischungen."
        onClick={() => nav.pushPanel('parents')}
      />
      <Row
        label="Augenfarbe"
        desc="9 realistische Farben."
        onClick={() => nav.pushPanel('eyeColour')}
      />
    </div>
  );
}