import { Caption, Row, send, type CreatorState, type PanelNav } from './creatorTypes';

/**
 * The creator's first panel: model choice, the six categories, and the
 * global actions.
 *
 * WHAT IT READS — and what it deliberately does NOT
 *
 * `renderRoot` (app.js:619-644) reads exactly one state field, `modelIsUndecided`,
 * and only to decide whether the two model buttons exist. It never looks at
 * `currentModel` or `characterGender`; both model buttons hardcode their hash as
 * their description. So there is no "which model am I currently" highlight here
 * and none is invented: `pickModel` on the Lua side sets `modelIsUndecided =
 * false`, which un-gates the block, and the block is only ever shown while the
 * player has not chosen.
 *
 * Every button is a straight pass-through. Ten of the eleven actions the vanilla
 * root fired are still registered one-for-one in cl_nui.lua; nothing is
 * renamed, nothing is merged.
 */

export interface RootProps {
  state: CreatorState;
  nav: PanelNav;
}

/**
 * The two subtitle strings renderRoot can produce, kept with the panel that owns
 * them so the shell cannot drift from the gate. Both strings are verbatim.
 */
export function rootSubtitle(modelIsUndecided: boolean): string {
  return modelIsUndecided
    ? 'Waehle ein Modell.'
    : 'Aussehen - Name und Stammdaten stehen bereits fest.';
}

export function Root({ state, nav }: RootProps) {
  const { modelIsUndecided } = state;

  return (
    <div className="flex flex-col gap-1.5">
      {modelIsUndecided ? (
        <>
          <Caption>Modell</Caption>
          <Row
            label="Maennlich"
            desc="mp_m_freemode_01"
            onClick={() => void send('pickModel', { model: 'mp_m_freemode_01' })}
          />
          <Row
            label="Weiblich"
            desc="mp_f_freemode_01"
            onClick={() => void send('pickModel', { model: 'mp_f_freemode_01' })}
          />
        </>
      ) : null}

      <Caption>Kategorien</Caption>
      <Row
        label="Heritage"
        desc="Eltern und Augenfarbe."
        onClick={() => nav.pushPanel('heritage')}
      />
      <Row
        label="Gesichtszuege"
        desc="Forme dein Gesicht."
        onClick={() => nav.pushPanel('faceFeatures')}
      />
      <Row label="Haare" desc="Frisur und Haarfarbe." onClick={() => nav.pushPanel('hair')} />
      <Row label="Makeup" desc="Bart, Make-up, Brauen." onClick={() => nav.pushPanel('makeup')} />
      <Row
        label="Tattoos"
        desc="Tattoos pro Koerperzone."
        onClick={() => nav.pushPanel('tattoos')}
      />
      <Row
        label="Outfit"
        desc="Kleidung und Accessoires."
        onClick={() => nav.pushPanel('outfit')}
      />

      <Caption>Aktionen</Caption>
      <Row label="Zufallsaufzug" onClick={() => void send('randomise', {})} />
      <Row label="Zufallschar" onClick={() => void send('randomiseAll', {})} />
      <Row label="Zuruecksetzen" onClick={() => void send('reset', {})} />
      <Row label="Kamera naeher" onClick={() => void send('zoomIn', {})} />
      <Row label="Kamera weiter" onClick={() => void send('zoomOut', {})} />
      <Row label="Fertig" variant="primary" onClick={() => void send('submit', {})} />
      <Row label="Abbrechen" variant="danger" onClick={() => void send('cancel', {})} />
    </div>
  );
}