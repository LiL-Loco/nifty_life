/**
 * The rulebook, as the application shows it.
 *
 * The canonical text lives in a Google Doc that the team edits. This module is
 * NOT a copy of it, deliberately: a duplicated rulebook drifts, and a rulebook
 * that has silently diverged from the one players agreed to is worse than no
 * rulebook at all.
 *
 * So this holds the two things that must not drift:
 *   1. the section structure, so the applicant sees what they are agreeing to,
 *   2. the rules that carry a PERMANENT ban, because those are the ones a
 *      reviewer needs a signed acknowledgement for.
 *
 * Everything else is read in the Doc, which is linked from here.
 */

export const RULEBOOK_URL =
  'https://docs.google.com/document/d/16AfnoT8c_Bs2nfCyoRV3CjwChOWL0tdPjcV-b0g3G0Y/edit';

/**
 * Shown only so the applicant knows what "the rulebook" contains. Headings
 * mirror the Doc; the wording under them does not, so a section that gains or
 * loses rules here cannot go stale in a way that misleads.
 */
export const RULEBOOK_SECTIONS: { ref: string; title: string }[] = [
  { ref: '§1', title: 'Allgemeines' },
  { ref: '§2', title: 'Trolling' },
  { ref: '§3', title: 'RDM / VDM' },
  { ref: '§4', title: 'Roleplay' },
  { ref: '§5', title: 'Voice' },
  { ref: '§6', title: 'Hinrichtungen, Suizid, Ausreisen' },
  { ref: '§7', title: 'Bewusstlosigkeit und die New-Life-Regel' },
  { ref: '§8', title: 'ATM, Raub, Geiselnahmen' },
  { ref: '§9', title: 'Gruppierungen, Gangs, Kriege' },
  { ref: '§10', title: 'LSPD' },
  { ref: '§11', title: 'Tier-Charaktere' },
  { ref: '§12', title: 'Sonstiges' },
];

/**
 * The four permanent-ban rules, asked individually.
 *
 * These are not the strictest rules in the document - §1 has others - they are
 * the ones where "I did not realise" is not an acceptable answer afterwards,
 * which is exactly what an acknowledgement is for.
 */
export const RULEBOOK_ACKNOWLEDGEMENTS: { key: string; label: string }[] = [
  {
    key: 'noSexRp',
    label:
      'Sex-RP ist in jeder Form und Weise verboten und führt zu einem sofortigen, dauerhaften Ban.',
  },
  {
    key: 'noHateSpeech',
    label:
      'Keine Beleidigungen, kein Extremismus, kein Rassismus, keine Diskriminierung. Auch keine Verharmlosungen.',
  },
  {
    key: 'noMetaGaming',
    label:
      'Meta-Gaming ist verboten und wird mit einem dauerhaften Ban geahndet. Das gilt auch für Changelogs und Ankündigungen.',
  },
  {
    key: 'noAccountOrCurrencyTrade',
    label:
      'Der Verkauf von Accounts und von Ingame-Währung gegen echtes Geld ist verboten und führt für beide Seiten zum Permaban.',
  },
];

export const RULEBOOK_KEYS = RULEBOOK_ACKNOWLEDGEMENTS.map((a) => a.key);