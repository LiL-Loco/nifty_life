/**
 * The rulebook, as the application asks about it.
 *
 * Until 2026-10-12 this file deliberately held NO copy of the rule text: the
 * canonical document was a Google Doc, and a duplicated rulebook drifts. A
 * drifted rulebook is worse than none, because it looks authoritative.
 *
 * The owner reversed that decision. A rulebook a visitor has to leave the site
 * for is a rulebook nobody reads, so the text now lives here and is rendered at
 * /regelwerk. The document is still where the team edits it; this is a copy
 * again, and the drift risk is real. It is accepted because readability won.
 *
 * What is here:
 *   1. the rule text itself, in RULEBOOK, plus the glossary,
 *   2. the section structure, DERIVED from that text, and
 *   3. twenty questions, each answerable in the applicant's OWN WORDS.
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

/** Where the rulebook is read: on this site, not on a document host. */
export const RULEBOOK_URL = '/regelwerk';

/**
 * The document the team edits. Nothing links here any more — it exists so the
 * edit path stays discoverable from the code, and so a future sync script has
 * one constant to read.
 */
export const RULEBOOK_SOURCE_URL =
  'https://docs.google.com/document/d/16AfnoT8c_Bs2nfCyoRV3CjwChOWL0tdPjcV-b0g3G0Y/edit';

export interface RulebookSection {
  ref: string;
  title: string;
  items: string[];
}

/**
 * The rulebook, as prose, on this site.
 *
 * It used to live only in a Google Doc and be linked from here. The owner
 * decided (2026-10-12) that a rulebook a visitor has to leave the site for is a
 * rulebook nobody reads, so the text now lives in the repository and is
 * rendered at /regelwerk. That reverses the reasoning in the note on
 * `RULEBOOK_REFERENCE_TEXT` below — which is why that constant is still empty
 * and copycheck is still off: turning the rule text into a copy that is compared
 * for verbatim lifting is a separate decision, and it should be made on purpose.
 *
 * `RULEBOOK_SECTIONS` is DERIVED from this list rather than maintained beside
 * it. The two used to be written independently, which is the arrangement that
 * lets an anchor point at a section that no longer exists.
 *
 * Verbatim from the document, with the paragraph breaks that the plain-text
 * export split mid-sentence rejoined. Nothing is reworded: this is the text the
 * applicants answered questions about.
 */
export const RULEBOOK: RulebookSection[] = [
  {
    ref: '§1',
    title: 'Allgemeines',
    items: [
      'Beleidigungen, Extremismus, Rassismus, sexuelle Belästigung und Diskriminierung von Minderheiten sowie das Darstellen geistiger oder körperlicher Behinderungen werden nicht geduldet. Das Nachspielen von Vergewaltigungen ist verboten.',
      'Sex-RP in jeglicher Art und Weise führt zu einem sofortigen, permanenten Ban ohne Aussicht auf Entbannung.',
      'Die N-Bombe wird auf unserem Server NICHT geduldet. Dazu zählen auch Verniedlichungen und/oder Abwandlungen.',
      'Das Ausnutzen von ungewollten Spielmechaniken, Bugs, Exploits, technischen Fehlern oder Lücken im Regelwerk wird bestraft. Diese sind umgehend im Support zu melden.',
      'Das Mindestalter beträgt 18 Jahre. Sollte das Team davon Kenntnis nehmen, dass ihr unter 18 seid, können wir euch im Nachhinein vom Projekt ausschließen.',
      'Die Nutzung von externen Programmen/Mods, die das Spielverhalten ändern könnten, wird bestraft. Dazu zählen auch externe Crosshairs.',
      'Die Kommunikation außerhalb der im Spiel zur Verfügung stehenden und vom Team erlaubten Mitteln ist untersagt.',
      'Verstöße gegen die Serverregeln werden mit sowohl temporären als auch permanenten Sperren bestraft.',
      'Alle hier aufgelisteten Regeln gelten für menschliche sowie auch für tierische Charaktere. Besonderheiten für Tiere werden gesondert beschrieben.',
      'Die Benutzung vom OOC-Chat (/ooc), InGame, ist nur bei schwerwiegenden Bugs wie z. B. „Hilfe, bin durch die Spielwelt gefallen." erlaubt.',
      'Es werden keine Fragen zu Spielmechaniken oder anderen Arten von Supportfällen im OOC-Chat geduldet.',
    ],
  },
  {
    ref: '§2',
    title: 'Trolling',
    items: [
      'Jegliche Art von Trolling ist untersagt. Dazu zählt unter anderem das vorsätzliche Stören/Provozieren von Fremden ohne RP-Hintergrund, Ausnutzen von Voice Lautstärke/Reichweite, usw.',
    ],
  },
  {
    ref: '§3',
    title: 'RDM/VDM',
    items: [
      'Spieler ohne RP-Hintergrund nieder zu schießen ist verboten.',
      'Fahrzeuge sind keine Waffen. Das Überfahren eines Spielers mit einem Fahrzeug ist verboten.',
      'Das unverhältnismäßige Rammen eines Spielers, der auf einem Motorrad unterwegs ist, ist verboten.',
    ],
  },
  {
    ref: '§4',
    title: 'Roleplay',
    items: [
      'Meta Gaming ist die Informationsbeschaffung außerhalb des RP’s. Meta Gaming wird mit einem Permaban bestraft.',
      'Power-RP ist das Erzwingen und Aufdrängen einer Situation, in der die andere Person keinen Handlungsfreiraum mehr hat.',
      'Einfach "Überfall!" rufen ist kein RP! Power RP ist strengstens untersagt.',
      'Einer Person durch sein eigenes RP den Tod aufzuzwingen, ohne genehmigten Hinrichtungsantrag, kann zu einem permanenten Bann führen.',
      'Verletzungen, die dem Spieler nach dem Erscheinen des Wasted-Timers zugefügt werden, müssen nicht ausgespielt werden.',
      'Jeder Spieler muss in seiner Rolle bleiben und sich realitätsnah verhalten. OOC-Talk ist strengstens untersagt.',
      'Dein Charaktername muss aus einem realistischen Vor- und Zunamen bestehen. Troll Namen wie "Gernhard Reinficken" und Namen existierender Personen, egal ob real oder fiktiv, werden nicht zugelassen oder nachträglich entfernt.',
      'Das Ausloggen während einer RP-Situation ist verboten. Game Crashes sind davon ausgeschlossen. Sollte es aus technischen Gründen nicht möglich sein das RP fortzusetzen, ist der Support darüber zu informieren.',
      'Das Ausloggen während der Bewusstlosigkeit ist verboten.',
      'Während man gefesselt ist, kann man keine Funkgeräte benutzen oder andere Aktionen ausführen, für die man die Hände benötigt.',
      'Das Tragen eines Bandanas um den Mundbereich gilt auf Nifty. Life bereits als Vollmaskierung.',
      'Maskierte Spieler dürfen nicht an ihrer Stimme, ihrem Dialekt, ihrem Rede- oder Kleidungsstil erkannt werden. Mehrere eindeutige Indizien können zu Verdächtigungen und Mutmaßungen führen.',
      'Auf Nifty. Life verzichten wir auf eine verbale Schussankündigung. Das pure ziehen der Waffe aus dem Hosenbund (Animation) kündigt den Gebrauch der Schusswaffe an.',
      'Sollte dein Gegenüber gegen Serverregeln verstoßen, bist du dazu verpflichtet, dein RP zu Ende zu bringen und dich erst im Anschluss an den Support zu wenden.',
      'Roleplay, das durch einen Serverrestart oder Servercrash unterbrochen wurde, muss nach dem Restart des Servers fortgesetzt werden.',
      'Scripted-RP ist strengstens untersagt.',
      'Regelverstöße werden nur mit Videobeweis oder VOD vom Support akzeptiert.',
    ],
  },
  {
    ref: '§5',
    title: 'Voice',
    items: [
      'Anwesenheit auf unserem Teamspeak-Server ist Pflicht, solange man sich Ingame aufhält.',
      'Mit dem Betreten des Servers erklärst du dich einverstanden, dass der Ingame-Voice-Chat aufgenommen und genutzt werden darf.',
      'Verbale Kommunikation ist zwingend erforderlich. Jeder Spieler hat Sorge zu tragen, dass er ein funktionstüchtiges Mikrofon besitzt.',
      'Störgeräusche müssen umgehend behoben werden.',
    ],
  },
  {
    ref: '§6',
    title: 'Hinrichtungen, Suizid, Ausreisen',
    items: [
      'Hinrichtungen können nur nach Absprache mit dem Support genehmigt werden und müssen genauestens mit RP-Hintergrund, der nachweislich keine andere Lösung bietet, begründet sein.',
      'Der Spieler, gegen den der Hinrichtungsantrag eingereicht wurde, erfährt nichts von diesem Antrag.',
      'Mediziner dürfen einen hingerichteten Spieler nicht wiederbeleben.',
      'Suizid darf NICHT begangen werden.',
      'Ausreisen müssen vom Support genehmigt werden. Alle laufenden RP-Stränge müssen beendet sein um Ausreisen zu können.',
    ],
  },
  {
    ref: '§7',
    title: 'Bewusstlosigkeit (New-Life-Regel)',
    items: [
      'Sobald ihr einen Timer unten auf eurem Screen seht, seid ihr bewusstlos.',
      'Solltet ihr bewusstlos sein und es ist kein Mediziner im Dienst, könnt ihr am Krankenhaus respawnen.',
      'Das "Respawnen" wird im Spiel als "Notfallmediziner" ausgespielt, die euch mit einem Helikopter ins Krankenhaus gebracht haben. Die "Notfallmediziner" behandeln euch nicht. Nach dem Transport bist du noch immer verletzt. Ausnahme: Sollte kein Mediziner im Dienst sein, behandeln euch die Notfallmediziner. Während der Bewusstlosigkeit erlangte Informationen dürfen nicht benutzt werden.',
      'Nachdem Du im Krankenhaus aufgewacht bist, darfst du dich der laufenden RP Situation nicht nähern.',
      'Der endgültige Tod kann nur durch eine Hinrichtung eintreten.',
      'Nach einer Hinrichtung wird der Charakter gelöscht.',
    ],
  },
  {
    ref: '§8',
    title: 'ATM, Raub, Geiselnahmen',
    items: [
      'Ein Spieler darf einen anderen Spieler nicht ohne triftigen Grund im Rollenspiel dazu zwingen, Geld vom ATM abzuheben.',
      'Geiselnahmen dürfen nicht aus niederen Beweggründen zB. Erpressung von Fraktionswaffen / Funkgeräten oder Freipressen von Gefangenen durchgeführt werden.',
      'Das vorsätzliche Entwenden von Fraktionswaffen & Funkgeräten ist untersagt.',
    ],
  },
  {
    ref: '§9',
    title: 'Gruppierungen, Gangs, Kriege',
    items: [
      'Eine Gruppierung darf aus maximal 10 Personen bestehen. 4 Personen aus einer Gruppierung dürfen an der selben illegalen Tätigkeit teilnehmen. (Beispiel: 4 Personen dürfen einen Banküberfall machen, weitere 4 Personen dürfen ATM’s knacken gehen)',
      'Gruppierungen dürfen keine Bündnisse gegen andere Parteien miteinander schliessen. Geschäftliche Beziehungen unter den Gruppierungen sind gestattet.',
      'Gangkriege müssen im Rollenspiel angekündigt und im Support angemeldet und abgesegnet sein.',
      'Gangkriege enden, wenn eine der beiden Parteien dauerhaft finanziell oder durch Mannstärke unterlegen ist, oder eine der beiden Parteien von alleine aufgibt. Niederlage und das Aufgeben müssen im Rollenspiel kommuniziert und vernünftig ausgespielt werden.',
      'Kollateralschäden werden im Rahmen eines Gangkriegs NICHT als RDM gewertet. Kollateralschäden sind allerdings - soweit möglich - zu vermeiden und sollten eine Ausnahme bleiben.',
      'Während des Gangkriegs muss jede Partei ganz klar sichtbar ihre Gang Farbe tragen. (Farbiges Oberteil ist hierbei Pflicht!)',
      'Die Polizei ist unabhängig von diesen Regelungen und fungiert als neutrale, dritte Partei.',
    ],
  },
  {
    ref: '§10',
    title: 'LSPD',
    items: [
      'Wenn ein Spieler von den Cops niedergeschlagen oder in Handschellen gelegt wird, gilt er als in Gewahrsam.',
      'Nach der Inhaftierung ist das aktuelle Verbrechensszenario beendet und wechselt zu einem Verhaftungs- / Ermittlungsszenario.',
      'Während eines Festnahme- / Ermittlungsszenarios dürfen sich Freunde der verhafteten Person/en nicht mehr einmischen und Zivilisten, die nicht zur Befragung oder Beteiligung benötigt werden, sollten das Gebiet verlassen.',
    ],
  },
  {
    ref: '§11',
    title: 'Tier-Charaktere',
    items: ['Ein Zusammenschluss von Tieren, also ein Rudel, ist nicht erlaubt.'],
  },
  {
    ref: '§12',
    title: 'Sonstiges',
    items: [
      'Der Verlust von Items, Fahrzeugen, Häusern etc. kann ausschließlich durch einen Videobeweis im Support geltend gemacht werden.',
      'Support Gespräche dürfen nicht aufgezeichnet werden.',
      'Das Verkaufen des Accounts ist verboten und führt zum Permaban der verkaufenden und kaufenden Person.',
      'Das Verkaufen von Ingame-Währung gegen Währungen außerhalb von Nifty. Life ist verboten und wird bestraft.',
      'Namensänderungen (zB. bei Heirat) müssen beim Support angefragt werden.',
      'Eine Namensänderung ist keine Erlaubnis euren RP-Charakter zu ändern (Charaktereigenschaften, Verhalten usw.)',
      'Während sich ein Spieler auf dem Server befindet, ist es absolut untersagt, Streams anderer Nifty. Life Spieler (Chat inbegriffen) zu verfolgen.',
      'Das Streamen und Aufzeichnen von Videos ist auf unserem Server gestattet und erfordert keine besondere Erlaubnis.',
      'Die gültigen Richtlinien der Streaming-/ Video Plattform sind zu beachten. Die Erwähnung des Servers im Titel des Streams etc. ist natürlich erwünscht. Vom Server ausgehende Gespräche werden nur nach Absprache mit dem Support aufgenommen (Community-Besprechungen etc.). Wir sind natürlich für Transparenz, möchten aber auch die Sicherheit und die Privatsphäre jedes Spielers wahren.',
      'Streamende Spieler verpflichten sich, während sie auf Nifty. Life spielen, OOC-Hate, RP-Bewertung und Stimmungsmache gegen anderer Spieler zu unterlassen. Der Chat ist jederzeit zu moderieren.',
      'Wiederholte Missachtung dieser Regel kann zum Ausschluss vom Projekt führen.',
      'Spieler müssen jederzeit die Nutzungsbedingungen von Twitch.tv (TOS) befolgen.',
      'Auf Twitch.tv gebannte Spieler dürfen nicht auf Nifty. Life spielen.',
    ],
  },
];

/** The glossary that precedes the rules, and answers most of what newcomers ask. */
export const GLOSSARY: { term: string; meaning: string }[] = [
  {
    term: 'In Character (IC)',
    meaning:
      'Steht für "In Character", sprich alles was im Spiel passiert. IC darf nur Wissen verwenden, welches man auch IC erlangt hat.',
  },
  {
    term: 'Out Of Character (OOC)',
    meaning:
      'Steht für "Out of Character" und ist all das, was nicht im Spiel passiert. OOC Sachen dürfen nicht IC verwendet werden.',
  },
  {
    term: 'RDM (Random Death Match)',
    meaning:
      'Andere Spieler in die Bewusstlosigkeit befördern, ohne zulässigen Hintergrund im Rollenspiel.',
  },
  {
    term: 'VDM (Vehicle Death Match)',
    meaning:
      'Absichtliches Über- und/oder Anfahren von Mitspielern. Fahrzeuge sind keine Waffen.',
  },
  {
    term: 'Meta',
    meaning:
      'Informationen nutzen, die ich OOC als Spieler erlangt habe, die mein Charakter IC, nicht wissen kann.',
  },
  {
    term: 'RP-Flucht',
    meaning:
      'Das vorsätzliche Verlassen des Servers während einer laufenden RP Situation.',
  },
  {
    term: 'RP-Verweigerung',
    meaning:
      'RP ist ein geben und nehmen. Wird mir RP geboten und ich stelle mich komplett quer und gehe nicht auf das RP ein, verweigere ich das RP und ich begehe eine "RP-Verweigerung".',
  },
  {
    term: 'Scripting',
    meaning: 'Planen von RP Aktionen außerhalb des Spiels.',
  },
  {
    term: 'Power-RP',
    meaning:
      'Meinen Mitspielern eine Situation aufzwingen, in der sie keinen Handlungsspielraum haben.',
  },
  {
    term: 'Changelogs / Ankündigungen',
    meaning:
      'Ankündigungen und Changelogs, die wir auf dem Discord mit euch teilen, sind IC nicht zu verwenden oder anzusprechen.',
  },
];

/** Ref and title only — what the application form anchors to. */
export const RULEBOOK_SECTIONS: { ref: string; title: string }[] = RULEBOOK.map(
  (section) => ({ ref: section.ref, title: section.title }),
);

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

/**
 * The rulebook wording, for the copied-answer check — EMPTY ON PURPOSE.
 *
 * `src/lib/copycheck.ts` can compare an answer against the actual rule text and
 * find a sentence lifted verbatim out of it. That is the check that matters most
 * and it does not run unless this string has content.
 *
 * It stays empty because the rulebook lives in one Google Doc and a copy here
 * would be a copy that drifts out of date silently — a detector comparing
 * against last year's wording is worse than no detector, because it still
 * reports success. Filling it in is a decision, not a chore: it means putting the
 * rule text in the repo, and it should be a deliberate act with a version
 * stamp next to it.
 *
 * Until then `copycheck` reports `rulebookTextAvailable: false` and the warning
 * text says only what was actually checked.
 */
export const RULEBOOK_REFERENCE_TEXT = '';