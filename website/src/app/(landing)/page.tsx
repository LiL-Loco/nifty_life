import Link from 'next/link';

import { config } from '@/lib/config';

/**
 * The landing page.
 *
 * One screen, two doors. It exists to send somebody to Discord or to the portal,
 * and everything here serves that decision.
 *
 * THE LOOK is built from what the reference screenshot actually shows rather
 * than from what a GTA server site usually looks like: a full-bleed background
 * darkened almost to black, a fine dot texture across it, the mark centred high,
 * and two stacked pill buttons with a heavy black outline. The composition and
 * the texture are the idea; the assets are ours.
 *
 * NO GTA SCREENSHOT. The reference uses one, and it is Rockstar's. What is here
 * instead is a CSS-only equivalent — a layered gradient standing in for a city
 * at night, plus the halftone dots done with repeating radial gradients. If you
 * drop a real background in `public/hero.jpg`, one line in globals.css picks it
 * up and nothing else changes.
 */
export default function LandingPage() {
  const invite = config.discordInvite;

  return (
    <main className="hero">
      <div className="hero-mark">
        <span className="hero-mark-top">Nifty</span>
        <span className="hero-mark-bottom">Life</span>
        <span className="hero-mark-version">2.0</span>
      </div>

      <div className="hero-doors">
        {invite ? (
          <a className="door" href={invite} rel="noopener noreferrer" target="_blank">
            <span className="door-label">Zum Discord</span>
          </a>
        ) : (
          // No invite configured yet. Disabled rather than hidden, because a
          // landing page with one button and no explanation looks broken.
          <span className="door is-off" aria-disabled="true">
            <span className="door-label">Zum Discord</span>
            <span className="door-note">Einladung folgt</span>
          </span>
        )}

        <Link className="door" href="/login">
          <span className="door-label">Zum Portal</span>
        </Link>
      </div>

      <p className="hero-foot">
        Freitag 19:00 bis Sonntag 22:00 · Ein Charakter pro Person
      </p>
    </main>
  );
}