import type { Metadata } from 'next';
import Link from 'next/link';

export const metadata: Metadata = {
  title: 'Nifty Life 2.0',
  description:
    'Ein Roleplay-Server fürs Wochenende. Freitag 19:00 bis Sonntag 22:00, eine Bewerbung, ein Charakter pro Person.',
};

const PRINCIPLES = [
  {
    title: 'Ein Charakter pro Person',
    body: 'Nicht mehrere Leben parallel, nicht FiveM-Charakter-Sammlung. Eine Identität, die über Wochen Bestand hat.',
  },
  {
    title: 'Offene Jobs',
    body: 'Jede offene Stelle in der Stadt ist auch für neue Leute offen. Du musst keine drei Bewerbungen für irgendeinen Neustart über dich ergehen lassen, um anfangen zu dürfen.',
  },
  {
    title: 'Nichts geht verloren',
    body: 'Montag bis Donnerstag ist der Server eingefroren, nicht gelöscht. Geld, Immobilien und Verlauf sind nächste Woche noch da.',
  },
  {
    title: 'Freezy bleibt Freezy',
    body: 'Die Grundsicherung zahlt jede Viertelstunde und ist absichtlich knapp bemessen. Wer mehr verdienen will, muss dafür arbeiten - aber niemand verhungert.',
  },
] as const;

export default function LandingPage() {
  return (
    <>
      <h1>Nifty Life 2.0</h1>
      <p className="lede">
        Ein Roleplay-Server fürs Wochenende. Freitag 19:00 geht's los, Sonntag 22:00
        ist Schluss. Alles, was du dir in diesem Wochenende aufbaust, bleibt für das
        nächste liegen.
      </p>

      <p style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
        <Link className="button" href="/login">
          Mit Discord anmelden
        </Link>
        <Link className="button secondary" href="/apply">
          Bewerben
        </Link>
      </p>

      <h2>Was hier anders ist</h2>
      <div className="card">
        {PRINCIPLES.map((item) => (
          <p className="small" key={item.title}>
            <strong>{item.title}.</strong> {item.body}
          </p>
        ))}
      </div>

      <h2>So kommst du rein</h2>
      <div className="card">
        <p className="small">
          <strong>1. Bewerben.</strong> Zwanzig Fragen, alle aus dem Regelwerk. Keine
          Multiple-Choice-Fragen, keine Formulare über dich - du schreibst in eigenen
          Worten, was gespielt wird und was nicht. Ein Mensch liest jede Bewerbung
          persönlich und entscheidet endgültig.
        </p>
        <p className="small">
          <strong>2. Freigeschaltet werden.</strong> Die Freigabe läuft über Discord.
          Nach der Ablehnung gibt es keine zweite Bewerbung - die Tür ist dann ein
          Gespräch, kein Formular.
        </p>
        <p className="small">
          <strong>3. Charakter verknüpfen.</strong> P&amp;R wird von Charakteren
          geschrieben, nicht von Konten. Im Spiel erzeugst du einen Code, gibst ihn
          auf der Website ein, und der Spielserver bestätigt die Verknüpfung. Die
          Website kann das nicht selbst bestätigen - das ist Absicht.
        </p>
        <p className="small">
          <strong>4. Spielen.</strong> Nur am Wochenende. Stimme ist Teamspeak, nicht
          ingame.
        </p>
      </div>

      <h2>Regeln, kurz</h2>
      <div className="card">
        <p className="small muted">
          Das vollständige Regelwerk ist das maßgebliche Dokument, und die
          Bewerbungsfragen decken es ab. Kurzfassung: IC und OOC bleiben getrennt,
          Wissen aus dem OOC wird nicht ins IC getragen, und es gibt ein paar Regeln,
          deren Bruch einen dauerhaften Ban bedeutet. Was davon konkret gilt, steht im
          Regelwerk - und wer es nicht gelesen hat, kann die Fragen nicht beantworten.
        </p>
      </div>

      <p className="small muted">
        Der Server ist noch nicht live. Bewerbungen werden erst angenommen, wenn alle
        Bereiche fertig sind.
      </p>
    </>
  );
}