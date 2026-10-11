/**
 * User-facing sentences that more than one page has to say.
 *
 * Only text that would otherwise be copy-pasted belongs here. A string that
 * appears on exactly one page stays on that page — a shared module full of
 * one-line constants is worse than a duplicate sentence, because it hides the
 * wording from the place somebody editing that page will look.
 */

/**
 * The introduction above the character form.
 *
 * Shown on /apply/character and /account/character, which render the same
 * `CharacterForm`. These two pages drifted apart once: the /account copy had
 * lost the sentence saying the first name is mandatory. One source, no drift.
 *
 * Keep it in step with the fields in `character-form.tsx`.
 */
export const CHARACTER_FORM_INTRO =
  'Vorname, Nachname, Geschlecht und Geburtsdatum. Der Vorname ist Pflicht; ' +
  'alles andere kann später im Spiel angepasst werden. Das Aussehen wird im ' +
  'Spiel eingestellt, nicht hier.';