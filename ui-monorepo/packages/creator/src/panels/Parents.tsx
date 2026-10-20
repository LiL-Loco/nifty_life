import * as React from 'react';
import { Caption, LabeledSlider, List, send, type CreatorState } from './creatorTypes';

/**
 * Eltern: the two presets, the similarity, the three blend weights and the skin
 * tone. Eight sliders and three stepped pickers over one Lua table.
 *
 * ---------------------------------------------------------------------------
 * THE NAME LISTS ARE BAKED IN BELOW, AND THAT IS A DELIBERATE DEVIATION
 * ---------------------------------------------------------------------------
 *
 * The portraits are built from a RUNTIME-CONSTRUCTED filename — `images/<Name>.webp`,
 * 46 files that exist in ui/images/ — so the panel needs the preset NAME for the
 * current index. Two sources were supposed to supply it and today neither does:
 *
 *   1. `state.labels.MOTHER` / `.FATHER` are Lua FUNCTIONS (cl_labels.lua:172-179),
 *      not arrays. A function has no JSON representation, so they never arrive.
 *      `|| []` in the vanilla version therefore produced three pickers with zero
 *      items: both arrows disabled, no portrait, no label.
 *   2. `state.parentNames` holds the REAL string arrays — but `buildPayload`
 *      (cl_nui.lua:146-162) forwards twelve keys and `parentNames` is not one of
 *      them, so it keeps its `[]` default.
 *
 * Both are one-line Lua fixes that this port is not allowed to make. So the two
 * name arrays are transcribed here from cl_labels.lua:160-171 and used ONLY when
 * the runtime arrays are empty — the moment Lua forwards `parentNames`, the
 * runtime value wins and these become dead. The portraits then work today and
 * keep working after the fix.
 *
 * WHY `creator:parentPortraits` IS NOT WIRED
 *
 * The brief asked for the portraits to arrive from that push, and the callback
 * exists (`requestParentPortraits`). It returns nothing: `captureParentPortrait`
 * is a stub returning `SILHOUETTE_PLACEHOLDER_BASE64`, and that constant is
 * `''` (cl_creator.lua:62,1337). The push therefore carries two EMPTY strings.
 * Feeding those into the <img> would replace working portraits with a broken
 * source — so the push is deliberately ignored, which is also what app.js did
 * (it only mentions the action in a comment at line 1163).
 *
 * ---------------------------------------------------------------------------
 * THE `resemblance` FIELD
 *
 * `headBlend` is built without it (cl_creator.lua:155-162), and `setHeadBlend`
 * does an untyped `face.headBlend[k] = v`, so the field is created by the first
 * drag of this very slider and read by nothing else. It is a write-only default
 * of 0.5. It is typed optional and defaulted at the read site, exactly as the
 * vanilla version did — with no invented Lua key.
 */

/** cl_labels.lua:160-165. Fallback for `state.parentNames.mother`. */
const MOTHER_NAMES = [
  'Hannah', 'Audrey', 'Jasmine', 'Giselle', 'Amelia', 'Isabella', 'Zoe',
  'Ava', 'Camila', 'Violet', 'Sophia', 'Evelyn', 'Nicole', 'Ashley',
  'Grace', 'Brianna', 'Natalie', 'Olivia', 'Elizabeth', 'Charlotte',
  'Emma', 'Misty',
];

/** cl_labels.lua:166-171. Fallback for `state.parentNames.father`. */
const FATHER_NAMES = [
  'Benjamin', 'Daniel', 'Joshua', 'Noah', 'Andrew', 'Juan', 'Alex',
  'Isaac', 'Evan', 'Ethan', 'Vincent', 'Angel', 'Diego', 'Adrian',
  'Gabriel', 'Michael', 'Santiago', 'Kevin', 'Louis', 'Samuel',
  'Anthony', 'Claude', 'Niko', 'John',
];

/** The 101 entries of the vanilla `ZtO` array: '0.00' … '1.00'. */
const Z_MAX = 100;
/** The 1001 entries of the vanilla `halfSteps` array: '0.0 %' … '100.0 %'. */
const W_MAX = 1000;

function clamp(value: number, max: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(max, Math.floor(value)));
}

/**
 * The subtitle line for this panel, verbatim from `parentsSummary` (app.js:221).
 * Exported because the subtitle belongs to the shell's chrome and would
 * otherwise have to be re-derived there.
 */
export function parentsSummary(headBlend: CreatorState['face']['headBlend']): string {
  const h = headBlend;
  const wm = h.motherWeight || 0;
  const wf = h.fatherWeight || 0;
  const wc = h.thirdWeight || 0;
  const total = wm + wf + wc;
  if (total <= 0) return 'Ergebnis: alle drei Anteile 0 %.';
  return `Ergebnis: Mutter ${((wm / total) * 100).toFixed(0)} %, Vater ${((wf / total) * 100).toFixed(0)} %, dritte Person ${((wc / total) * 100).toFixed(0)} %`;
}

/**
 * One preset portrait. The filename is built at render time from the preset
 * name, and a failed load hides the image — the vanilla `onerror` — so a missing
 * webp degrades to the name text underneath instead of a broken-image glyph.
 */
function Portrait({
  caption,
  name,
  presetIndex,
}: {
  caption: string;
  name: string;
  presetIndex: number;
}) {
  const [broken, setBroken] = React.useState(false);
  const src = name ? 'images/' + name + '.webp' : '';
  const fallback = caption + ' ' + presetIndex;

  React.useEffect(() => {
    setBroken(false);
  }, [src]);

  return (
    <div className="flex flex-col items-center gap-1.5 rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-background)] p-2">
      <span className="text-[10px] uppercase tracking-[0.18em] text-[var(--color-muted-foreground)]">
        {caption}
      </span>
      {src && !broken ? (
        <img
          src={src}
          alt={name || fallback}
          onError={() => setBroken(true)}
          className="h-36 w-36 rounded-[2px] border border-[var(--color-foreground)]/20 bg-[var(--color-secondary)] object-cover"
        />
      ) : null}
      <span className="text-[11px] tracking-[0.06em] text-[var(--color-muted-foreground)]">
        {name || fallback}
      </span>
    </div>
  );
}

export interface ParentsProps {
  state: CreatorState;
}

export function Parents({ state }: ParentsProps) {
  const h = state.face.headBlend;

  // Runtime first, baked-in second. One list per gender feeds BOTH the picker
  // labels and the portrait filenames — mixing a 1-based label array with a
  // 0-based name array would put the wrong face under the right name.
  const motherNames = state.parentNames?.mother?.length ? state.parentNames.mother : MOTHER_NAMES;
  const fatherNames = state.parentNames?.father?.length ? state.parentNames.father : FATHER_NAMES;
  // THIRDPERSON IS a real array and does arrive; the fallback is exactly the
  // same list in the same order (father block then mother block).
  const thirdNames = state.labels?.THIRDPERSON?.length
    ? state.labels.THIRDPERSON
    : [...FATHER_NAMES, ...MOTHER_NAMES];

  const motherIndex = h.mother || 0;
  const fatherIndex = h.father || 0;
  const thirdIndex = h.third || 0;

  return (
    <div className="flex flex-col gap-1.5">
      <div className="grid grid-cols-2 gap-2 rounded-[var(--radius-panel)] border border-[var(--color-border)] bg-[var(--color-secondary)] p-3">
        <Portrait caption="Mutter" name={motherNames[motherIndex] || ''} presetIndex={motherIndex} />
        <Portrait caption="Vater" name={fatherNames[fatherIndex] || ''} presetIndex={fatherIndex} />
      </div>

      <Caption>Personen</Caption>
      <List
        label="Mutter"
        items={motherNames}
        index={motherIndex}
        onChange={(i) => void send('setHeadBlend', { mother: i })}
      />
      <List
        label="Vater"
        items={fatherNames}
        index={fatherIndex}
        onChange={(i) => void send('setHeadBlend', { father: i })}
      />
      {thirdNames.length > 0 ? (
        <List
          label="Dritte Person"
          items={thirdNames}
          index={thirdIndex}
          onChange={(i) => void send('setHeadBlend', { third: i })}
        />
      ) : null}

      <Caption>Aehnlichkeit</Caption>
      <LabeledSlider
        label="Aehnlichkeit"
        value={clamp((h.resemblance != null ? h.resemblance : 0.5) * Z_MAX, Z_MAX)}
        max={Z_MAX}
        format={(i) => (i / 100).toFixed(2)}
        onChange={(i) => void send('setHeadBlend', { resemblance: i / 100 })}
      />

      <Caption>Anteile</Caption>
      <LabeledSlider
        label="Mutter-Anteil"
        value={clamp((h.motherWeight != null ? h.motherWeight : 0.5) * W_MAX, W_MAX)}
        max={W_MAX}
        format={(i) => `${(i / 10).toFixed(1)} %`}
        onChange={(i) => void send('setHeadBlend', { motherWeight: i / 1000 })}
      />
      <LabeledSlider
        label="Vater-Anteil"
        value={clamp((h.fatherWeight != null ? h.fatherWeight : 0.5) * W_MAX, W_MAX)}
        max={W_MAX}
        format={(i) => `${(i / 10).toFixed(1)} %`}
        onChange={(i) => void send('setHeadBlend', { fatherWeight: i / 1000 })}
      />
      <LabeledSlider
        label="Anteil dritte Person"
        value={clamp((h.thirdWeight != null ? h.thirdWeight : 0.0) * W_MAX, W_MAX)}
        max={W_MAX}
        format={(i) => `${(i / 10).toFixed(1)} %`}
        onChange={(i) => void send('setHeadBlend', { thirdWeight: i / 1000 })}
      />

      <Caption>Hautton</Caption>
      <LabeledSlider
        label="Hautton"
        value={clamp((h.skinTone != null ? h.skinTone : 0.5) * Z_MAX, Z_MAX)}
        max={Z_MAX}
        format={(i) => (i / 100).toFixed(2)}
        onChange={(i) => void send('setHeadBlend', { skinTone: i / 100 })}
      />
    </div>
  );
}