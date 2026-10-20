# 0026 — NUI-Panels werden React + shadcn, gebaut auf dem Spielserver

Status: accepted
Date: 2026-10-20
Supersedes: Zeile 38 von [ADR-0023](0023-own-menu-framework-in-nui.md) ("Still no build step")

## Kontext

ADR-0023 hat festgelegt: **kein Build-Step** für die NUI. Plain HTML/CSS/JS,
serviert aus `ui_page`. Das war die Voraussetzung dafür, dass eine eigene
Implementierung gegenüber LemonUI überhaupt trägt — kein npm, kein Bundler,
kein TypeScript in einem Lua-Projekt.

Diese Entscheidung hat zwei Kosten, die inzwischen real sind.

**1. Der Panels haben keine gemeinsame Basis.** Jede Ressource hat ihr eigenes
`fetchNui`, sein eigenes `el()`, seine eigene `button()`-Fabrik, sein eigenes
`.hidden`, seine eigenen Farb-Tokens. Bei sechs Panels sind das rund 1 000
Zeilen, die nur existieren, weil es keinen Ort gibt, an dem sie einmal zu
existieren brauchen.

**2. Zwei Fehlerklassen, die ein Typensystem beim Bauen gefunden hätte.**

*Aktions-Kollisionen.* Jede `ui_page` ist ein eigener CEF-Browser, und **alle**
Frames teilen sich einen `SendNUIMessage`-Kanal. Ein blankes `action = 'open'`
erreicht deshalb jede Ressource. Drei Panels hatten ein `open`; `nifty-world`
trug ein totes Creator-Formular mit genau diesem Namen, das sich über den echten
Creator legte und dessen Klicks schluckte. Das Ergebnis war ein sichtbares Menü
mit toten Buttons — ein Symptom, das auf Fokus, CSS und Kamera zeigt und auf
nichts davon zutrifft. `IsNuiFocused` meldet ehrlich `1`; es liest die
Buchführung des Spiels, nicht den Frame.

*Export-Argument-Versatz.* FiveM konsumiert ein implizites erstes Argument bei
einem Export-Aufruf. `Focus.acquire(RESOURCE)` übergibt `(nil, RESOURCE)`,
`Focus:acquire(RESOURCE)` übergibt `(RESOURCE)`. Beide kompilieren, beide geben
einen Boolean zurück, und der einzige Unterschied ist, ob der Ressourcenname
ankommt. Drei Aufrufer nutzten den Punkt, einer den Doppelpunkt — und genau der
eine funktionierte.

Ein dritter Befund, den es ebenfalls gab: `RegisterNetEvent` auf einem
**Client**-Event, das der Server per `TriggerClientEvent` schickt. `eventSource`
ist dann `net`, und ohne das Flag wird das Event verworfen. Ergebnis: schwarzer
Creator.

Keiner dieser drei Fehler ist im Nachhinein billig zu finden gewesen. Alle drei
haten ein Symptom, das auf eine andere Ebene zeigte.

## Entscheidung

Die NUI-Panels werden auf **React + shadcn/ui + Vite + TypeScript** umgestellt.
Gebaut wird **auf dem Spielserver**, weil dort kein GitHub Actions zur Verfügung
steht und der Server die einzige Maschine ist, die ohnehin deployed wird.

**Build-Ort.** `/root/ui-monorepo` auf der VPS, Bun als Package-Manager. Bun
installiert die 131 Pakete in ~570 ms; die Alternative (Node 20 + npm) ergibt
dieselbe Architektur und ist der eingebaute Fallback, falls Bun auf einer
künftigen glibc-Version ausfällt. Ausgeliefert wird nach
`resources/[nifty]/<ressource>/ui/dist/`.

**Warum hier und nicht geteilt mit ADR-0023.** ADR-0023 schlug eine geteilte
Ressource `nifty-ui` mit einer LemonUI-artigen API vor, in der `nifty-creator`
sein `index.html` vollständig verliert und zu Lua wird, das ein Menü baut. Das
Ziel ist nach wie richtig und **bleibt offen** — es ist eine andere Frage als
die nach dem Werkzeug. Diese ADR entscheidet nur, **womit** die Panels gebaut
werden, nicht **ob** sie eines Tages zusammengeführt werden.

**Warum React, das Shadcn für diese Panels weitgehend überflüssig macht.**
shadcn löst Popover, Dialog, Dropdown, Combobox und Fokus-Falle. Von denen ist
hier genau eine relevant — die drei Modals im Inventar. Der Rest ist
`button`, `input`, `label`, `separator`: 60 Zeilen CSS, die es bereits gab.
Der Wert liegt nicht in den Primitive, sondern in drei Dingen, die React
strukturell erzwingt und die hier real waren:

- **Aktionen sind typisiert.** `@nifty/bridge` nimmt die Aktionsliste des
  Panels entgegen; `on('open', …)` kompiliert für ein Creator-Panel nicht.
  Eine Kollision wird ein Build-Fehler statt eines stillen Nichts.
- **Kein geteilter Zustand.** Der Creator hatte ein einzelnes mutables
  Objekt, das an ~40 Stellen direkt beschrieben wurde.
- **Listener werden abgeräumt.** `renderFaceBones` registrierte pro
  `mousedown` zwei `window`-Listener und **entfernte sie nie** — bei 24 Knochen
  und 30 Hz sind das rund 1 440 Registrierungen pro Sekunde, solange das
  Gesichtspanel offen ist. Dasselbe Muster in vier Widget-Fabriken. React
  beheilt das nicht von allein, aber Refs und ein einziger Effekt machen es
  unmöglich, es zu vergessen.

## Folgen

- **`ui/dist/` wird committet, nicht ignoriert.** `.gitignore` hatte `dist/`
  unverankert, wodurch jedes Panel-Artefakt stillschweigend unversioniert
  geblieben wäre: kein Fehler, keine Warnung, nach einem Checkout fehlt die
  Datei und jeder `ui_page` zeigt ins Leere. Die Regel ist jetzt verankert.
  Ein Spielserver wird aus einem Checkout deployed — das Artefakt muss
  versionierbar bleiben, sonst ist es eine Vorbedingung, die jemand erfüllen
  muss, bevor er den Server übernimmt.
- **Die Lua-Seite ändert sich nicht.** Kein `RegisterNUICallback`, kein
  `SendNUIMessage`, kein Export wird angefasst. Der Brücken-Code ist pro
  Ressource generiert, nicht prozedural. Wenn am Ende ein Panel nichts mehr
  aufruft, liegt der Fehler im neuen TypeScript — nicht in einem Lua-Export,
  der vorher funktioniert hat.
- **Ein Ressourcen-Rebuild ersetzt kein `git pull`.** `bun install && bun run
  build` in `/root/ui-monorepo`, danach `dist/` in die Ressource kopieren. Ein
  `deploy.sh` bündelt beides mit dem Neustart.
- **ADR-0023 Zeile 38 ist hiermit superseded.** Die Aussage „kein Build-Step"
  gilt für die Panels nicht mehr. Sie gilt weiterhin für alles, was kein Panel
  ist.

## Was offen bleibt

`nifty-ui` als geteilte Ressource (ADR-0023) ist nicht umgesetzt. Wenn sie kommt,
sind die Panels Konsumenten einer gemeinsamen Oberfläche statt sechs eigener —
und die ~1 000 Zeilen duplizierte `fetchNui`/`el()`/`button()` verschwinden.
Diese ADR sagt nichts dagegen; sie räumt nur das Werkzeug.

## Verifikation

Ein Panel gilt als fertig, wenn: `bun run build` auf der VPS durchläuft,
`ui_page` auf eine existierende Datei zeigt, `files` alle referenzierten Assets
deckt, der Server mit `grep -c "script error"` == 0 startet, und das Panel im
Spiel dieselben Aktionen zeigt wie vorher — bei einem Creator-Charakter
insbesondere: Regler bewegen das Gesicht, „Fertig" speichert, ESC gibt den
Fokus frei.