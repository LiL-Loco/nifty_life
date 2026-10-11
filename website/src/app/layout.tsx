import type { Metadata } from 'next';

import './globals.css';

export const metadata: Metadata = {
  title: 'Nifty Life 2.0',
  description:
    'Ein Roleplay-Server fürs Wochenende. Bewerben, Status prüfen, P&R lesen.',
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
      <body>{children}</body>
    </html>
  );
}