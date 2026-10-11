/**
 * The rulebook, as the application asks about it.
 *
 * The canonical text lives in a Google Doc the team edits. Nothing here copies
 * it — a duplicated rulebook drifts, and a rulebook that has silently diverged
 * from the one players agreed to is worse than none.
 *
 * What is here instead:
 *   1. the section structure, so an applicant sees the scope of what they agree
 *      to, and
 *   2. twenty questions, each answerable in the applicant's OWN WORDS.
 *
 * Every question is answerable from the rulebook and from nothing else. There is
 * no multiple choice anywhere: a checkbox answers nothing, and a reviewer needs
 * to see whether the applicant understood the rule or merely recognised the word.
 *
 * The four rules that carry a permanent ban are asked about like any other
 * question. Asking them separately as "do you accept this?" produced a reflex
 * answer, not a considered one — a free-text question forces the applicant to
 * restate the rule in their own words, which is the only version of consent that
 * survives a moderation argument six months later.
 */

export const RULEBOOK_URL =
  'https://docs.google.com/document/d/16AfnoT8c_Bs2nfCyoRV3CjwChOWL0tdPjcV-b0g3G0Y/edit';

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

export interface RulebookQuestion {
  /** Stable id. It is stored with the answer, so a reworded question does not
   *  orphan an old application's answers. */
  id: string;
  ref: string;
  question: string;
}

/**
 * Twenty questions, in rulebook order.
 *
 * Order follows the document so a reviewer reading the answers reads them in the
 * same sequence as the rules.
 */
export const RULEBOOK_QUESTIONS: RulebookQuestion[] = [
  {
    id: 'q01',
    ref: '§1',
    question:
      'Was bedeuten IC und OOC, und warum darf Wissen aus dem OOC nicht im IC verwendet werden?',
  },
  {
    id: 'q02',
    ref: '§1',
    question:
      'Du liest im Discord eine Ankündigung oder einen Changelog. Darfst du dieses Wissen im IC verwenden? Erkläre, warum.',
  },
  {
    id: 'q03',
    ref: '§3',
    question: 'Was unterscheidet RDM von VDM?',
  },
  {
    id: 'q04',
    ref: '§3',
    question:
      'Warum sind Fahrzeuge laut Regelwerk keine Waffen? Und was ist beim Rammen eines Motorradfahrers besonders zu beachten?',
  },
  {
    id: 'q05',
    ref: '§4',
    question: 'Was ist Meta-Gaming, und welche Strafe steht laut Regelwerk darauf?',
  },
  {
    id: 'q06',
    ref: '§4',
    question: 'Was ist Power-RP, und warum reicht es nicht, einfach "Überfall!" zu rufen?',
  },
  {
    id: 'q07',
    ref: '§4',
    question: 'Du wirst während einer laufenden RP-Situation getrennt oder das Spiel stürzt ab. Was musst du tun?',
  },
  {
    id: 'q08',
    ref: '§4',
    question:
      'Ein anderer Spieler bietet dir RP an und du willst nicht darauf eingehen. Wie gehst du damit laut Regelwerk um?',
  },
  {
    id: 'q09',
    ref: '§5',
    question:
      'Welche Pflichten hast du auf dem Teamspeak, wenn du dich im Spiel aufhältst, und was gilt für dein Mikrofon?',
  },
  {
    id: 'q10',
    ref: '§6',
    question:
      'Wodurch unterscheidet sich ein genehmigter Hinrichtungsantrag von einem RP, in dem du einer Person einfach den Tod aufzwingst?',
  },
  {
    id: 'q11',
    ref: '§6',
    question:
      'Du willst ausreisen. Was musst du vorher beachten, und was passiert mit laufenden RP-Strängen?',
  },
  {
    id: 'q12',
    ref: '§7',
    question:
      'Du siehst den Wasted-Timer. Was bedeutet das, und was kannst du tun, wenn kein Mediziner im Dienst ist?',
  },
  {
    id: 'q13',
    ref: '§7',
    question:
      'Warum darfst du dich nach dem Aufwachen im Krankenhaus nicht der laufenden RP-Situation nähern? Was gilt für Informationen, die du bewusstlos erlangt hast?',
  },
  {
    id: 'q14',
    ref: '§7',
    question:
      'Wer darf einen hingerichteten Spieler wiederbeleben, und was passiert danach mit dem Charakter?',
  },
  {
    id: 'q15',
    ref: '§8',
    question: 'Wann ist eine Geiselnahme untersagt? Nenne zwei Beispiele aus dem Regelwerk.',
  },
  {
    id: 'q16',
    ref: '§9',
    question:
      'Wie viele Personen darf eine Gruppierung haben, und wie viele dürfen gleichzeitig an derselben illegalen Tätigkeit teilnehmen?',
  },
  {
    id: 'q17',
    ref: '§9',
    question:
      'Was musst du während eines Gangkriegs sichtbar tragen, und wann endet ein Gangkrieg laut Regelwerk?',
  },
  {
    id: 'q18',
    ref: '§10',
    question:
      'Du wirst von der Polizei niedergeschlagen oder in Handschellen gelegt. Was gilt ab diesem Moment für das laufende RP?',
  },
  {
    id: 'q19',
    ref: '§1',
    question:
      'Wann ist die Nutzung des OOC-Chats erlaubt, und wann nicht? Gib je ein Beispiel für beides.',
  },
  {
    id: 'q20',
    ref: '§12',
    question:
      'Was ist beim Streamen erlaubt und was nicht, und welche Pflichten hast du als streamender Spieler auf diesem Server?',
  },
];

export const RULEBOOK_QUESTION_IDS = RULEBOOK_QUESTIONS.map((q) => q.id);