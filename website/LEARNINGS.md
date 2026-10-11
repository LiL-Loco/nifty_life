# Learnings

- [2026-10-11] Regel: Keine Route-Namen (`/account`, `/apply`, `/status`) in Fließtext, der Besuchern angezeigt wird. Verweise auf Seiten über Linktexte ("im Konto", "unter Status") – eine URL ist ein Implementierungsdetail. Betraf login/page.tsx und register/done/page.tsx.
- [2026-10-11] Regel: Keine GRANT-/Datenbank-Begründung in Besuchertext. Die Begründung, warum es keinen Knopf gibt, gehört in den Code-Kommentar, nicht in die Oberfläche. Betraf status/page.tsx und peeper/pair/page.tsx.
- [2026-10-11] Fakt: Das Portal ist auf Deutsch und benutzt durchgehend "du" (informell). Anrede in neuem Text beibehalten.
- [2026-10-11] Fakt: Gedankenstrich im Besuchertext ist immer `—` (Em Dash), nie `-` als Satzzeichen. Drei Stellen wichen ab und wurden korrigiert.
- [2026-10-11] Fakt: Die Texte sind bewusst kurz und konkret geschrieben. Kein blanket-Rewrite von Seiten, die bereits so klingen – das verschlechtert sie. Bei Copy-Änderungen nur echte Defekte anfassen (Raw Routes, GRANT-Leaks, Doppel-Em-Dash, Duplikate).
- [2026-10-11] Fakt: `/apply/character` und `/account/character` teilen denselben Einleitungstext. Er kommt jetzt aus `CHARACTER_FORM_INTRO` in `src/lib/copy.ts` – dort landet jeder Besuchertext, den mehrere Seiten brauchen.
- [2026-10-11] Regel: Der Name des Session-Cookies steht als `SESSION_COOKIE` in `src/lib/session.ts`. Nie als Literal `'nifty_session'` – das war an sechs Stellen kopiert, ein Rename wäre stillschweigend wirkungslos gewesen. Das OAuth-State-Cookie bleibt Literal (nur zwei direkt benachbarte Stellen).
- [2026-10-11] Fakt: `src/components/login-form.tsx` (LoginForm) ist die einzige Login-/Registrierungs-Form. Das gleichnamige `app/(site)/login/form.tsx` war eine ältere, nie importierte Variante und ist weg.