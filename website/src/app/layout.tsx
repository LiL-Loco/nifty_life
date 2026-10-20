import type { Metadata, Viewport } from 'next';

import './globals.css';

export const metadata: Metadata = {
  title: 'Nifty Life 2.0',
  description:
    'Ein Roleplay-Server fürs Wochenende. Bewerben, Status prüfen, P&R lesen.',
};

/**
 * Dark-only site: the browser chrome follows the panels and the loading
 * screen, which are all near-black. Without this the address bar renders light
 * against a black page on a default theme.
 */
export const viewport: Viewport = {
  themeColor: '#000000',
};


/**
 * Deliberately bare: no header, no footer, no width constraint.
 *
 * The landing page is a full-bleed hero with its own composition, and forcing it
 * through the portal's centered column turned it into a page of chrome around a
 * logo. So the chrome lives in `app/(site)/layout.tsx` and only the pages that
 * want it inherit it. A route group does not appear in the URL: /apply is
 * /apply, not /(site)/apply.
 */
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="de">
      <head>
        {/*
          Theme fonts (Tema 1) — same URL the NUI panels and the loading screen
          use, so all three surfaces render one typeface for the whole session.
          The system stack in --font-sans is what shows until the webfont
          arrives; the two are close enough in weight that the swap is not a
          visible shift.
        */}
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;600;800&family=IBM+Plex+Mono:wght@400;600&display=swap"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}