# terravia-ops-radar

Game Guardian (Lua) Port des [Critical-Ops-External](https://github.com/islavikfx/Critical-Ops-External) Menüs von islavikfx.

Das C++-Tool patcht Code-Bytes in `libil2cpp.so`, um im Spiel eingebaute Funktionen freizuschalten:
- **Radar/ESP** (Espradar)
- **Hitboxes** (größere Trefferboxen)
- **Wallshot** (Schüsse durch Wände)

Dieses Script macht genau das über Game Guardian — ohne PC, ohne Termux, direkt auf dem Handy.

## Nutzung

1. Game Guardian mit Root auf das Handy
2. Critical Ops starten, in GG den Prozess `com.criticalforceentertainment.criticalops` auswählen
3. `terravia_ops_radar.lua` in GG ausführen
4. Features im Menü ein-/ausschalten (Radar ESP / Hitboxes / Wallshot)

## Wichtig — Offsets pro Spielversion

Die Offsets im Script sind Standardwerte. Jedes Update von Critical Ops ändert die Code-Adressen in `libil2cpp.so`.
Das Script prüft vor jedem Patch, ob die Bytes an der Zieladresse zu den erwarteten Original-Bytes passen.
Stimmen sie nicht, kommt eine klare Meldung — das Spiel wird **nicht** beschädigt, es wird einfach nicht gepatcht.

Offsets anpassen: Werte oben im Script in der Tabelle `OFFSETS` ändern, oder in
`/sdcard/Download/terravia_ops_radar_offsets.lua` (wird automatisch beim ersten Lauf erzeugt und geladen).

## Struktur

- `terravia_ops_radar.lua` — das GG-Script
- `README.md` — diese Datei

## Hinweise

- Der AC-Bypass aus dem Original-Repo wurde **bewusst nicht** übernommen (Offsets wurden vom Autor entfernt).
- Ohne funktionierenden AC-Bypass kann der Patch von der Anti-Cheat-Erkennung zurückgesetzt werden.
- Nutzung auf eigenes Risiko. Nur für Bildungszwecke / lokales Testen.
