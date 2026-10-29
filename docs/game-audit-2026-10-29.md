# Spieleprüfung – 29. Oktober 2026

Geprüft wurde die bestehende DateNight.io-App mit zwei getrennten Browser-Kontexten und echten Supabase-Testprofilen. Ein Spieler spielte am Desktop (1440 × 900), der zweite im mobilen Layout (375 × 812, zusätzlich 320 × 568). Keine simulierte Multiplayer-Verbindung. Die Browserläufe nutzten den lokalen Produktionsbuild mit der bestehenden Supabase-Datenbank.

## Ergebnisse je Spiel

| Spiel | Durchgespielter Ablauf | Befund und Umsetzung |
| --- | --- | --- |
| Herbert | Zehn Runden, geheim ansehen, private Ziehkarte, tauschen, FERTIG, letzter Gegnerzug, kumulierte Punkte und neue Serie | Eine veraltete Revision konnte FERTIG ablehnen, während der Dialog trotzdem verschwand. Vor der Bestätigung wird der aktuelle Stand gelesen; bei Fehlern bleibt der Dialog mit Erklärung offen. Alle zehn Runden anschließend bestanden. |
| Daily Us | Zwei Antworten, gemeinsame Aufdeckung; zusätzlich Rückkehr aus dem Glücksrad-Modus | Der Abschluss hatte keinen Weg zum nächsten zufälligen Spiel. „Neues Spiel drehen“ ergänzt und mit beiden Geräten geprüft. Der bereits beantwortete Tag bleibt erhalten. |
| This or That | Zehn Runden mit gleichen und unterschiedlichen Antworten, Ergebnis | In diesem Ablauf kein neuer Funktionsfehler gefunden. |
| Do You Know Me? | Zehn Runden mit wechselnder beurteilender Person, Ergebnis | In diesem Ablauf kein neuer Funktionsfehler gefunden. |
| Deep Talk | Zehn Karten bis zum Abschluss, Speichern einer Karte | Ablauf abgeschlossen. Nicht jede Karte des gesamten Fragenbestands inhaltlich geprüft. |
| Draw Together | Gemeinsames freies Zeichnen und Abschluss; sechs Runden Wörter erraten | Fehlerhafte Namensformulierung korrigiert; Beschriftungen der Zeichenwerkzeuge ins Deutsche übertragen. |
| Snake² | Gegeneinander und miteinander, Steuerung und Wandkollision, Ergebnis und Neustart | Beide Verlustabläufe bestanden. Wachstum, Beschleunigung, Nahrung und Team-Sieg zusätzlich durch Regeltests geprüft, kein kompletter Team-Sieg im Browser erspielt. |
| Relationship Bomb | Acht Module, gemeinsame Eingaben, Entschärfung ohne Fehler | Schwierigkeit synchronisiert und nach Bereitschaft gesperrt. Lückenhafte Schnellwahl konnte zu früh als vollständig gelten: korrigiert. Gespeicherte Antworten nicht mehr bearbeitbar; Ergebnis zeigt auch Rankings und Mehrfachauswahl. Timer stoppt nach Spielende. Mehrdeutige Rätselhinweise überarbeitet. |
| Moral Sync | Fünf Dilemmas einschließlich Reflexion und Ergebnis | Unterschiedliche lokale Rundenzahlen beseitigt. Themen/Tiefgang folgen dem gemeinsamen Spielstand. Nach Bereitschaft keine Änderung mehr. Weiter-Button benennt Reflexion beziehungsweise Ergebnis korrekt. Nachtest: beide sehen fünf Runden. |
| Rank | Drei Runden, Umordnen auf dem Handy, gemeinsame Aufdeckung und Ergebnis | Lokal abweichende Rundenzahl beseitigt. Nachtest: beide sehen drei Runden und dieselbe Sperre nach Bereitschaft. |
| Flipper Duo | Drei Bälle, beide Flipper, gemeinsames Ergebnis und Rematch | Abschuss war zu schwach für die Bumper. Verstärkt; anschließend 6.975 gemeinsame Punkte im Browserlauf. Trefferbeitrag wird durch echte Ballkontakte bestimmt, nicht allein durch Gedrückthalten einer Taste. Ergebnislayout für kleine Handys verkleinert, damit Neustart erreichbar bleibt. |
| Dots & Dates | Brett bis zu 16 geschlossenen Kästchen, Gesprächskarten und Ergebnis | Vollständiger Ablauf bis 8:8 erreicht. Zugrecht, Zusatz-Zug, ungültige Züge, Karten und Rematch zusätzlich durch Datenbanktests abgedeckt. Linien haben nun eindeutige zugängliche Bezeichnungen für waagrechte/senkrechte Richtung. |

## Übergreifende Korrekturen

- Nach Verlassen eines Spiels startet die nächste Auswahl eine neue Runde, statt einen alten unfertigen Stand wiederherzustellen. Gleichzeitiges Auswählen desselben aktiven Spiels erzeugt keine zweite Partie. Alte Daten werden nicht gelöscht und es werden keine künstlichen Abschlussbelohnungen vergeben.
- Fehlgeschlagene Abfragen privater Antworten werden automatisch erneut versucht; bisher konnte die Anzeige bis zur nächsten Spielaktion hängen bleiben.
- Verbindungsfehlermeldung ins Deutsche übertragen.
- Ergebnisansichten passen auf kurze Handybildschirme; bei wenig Platz entfällt die dekorative Trophäe zugunsten des Neustart-Buttons.

## Verifikation

- `npm test`: 59 Tests, 57 bestanden, 2 übersprungen, 0 fehlgeschlagen. Die zwei optionalen Live-Tests benötigen eigene Test-Umgebungsvariablen. Die oben genannten Browserprüfungen liefen unabhängig davon mit echtem Supabase.
- `npm run lint`: bestanden.
- `npm run build -- --webpack`: bestanden, einschließlich TypeScript.
- Neue Regressionstests: vollständige Schnellwahl und Ergebniszusammenfassung bei Bomb, realistischer Flipper-Abschuss und Trefferzuordnung, frische/idempotente Spielauswahl mit unveränderten alten Ergebnissen und Zugriffsschutz.
- Additive Migration: `supabase/migrations/20261029163337_game_selection_fresh_sessions.sql`. Ändert ausschließlich die bestehende Spielauswahl-Funktion; keine Tabellenänderung und keine Datenlöschung. Im DateNight.io-Projekt angewendet und anschließend im Browser bestätigt.

## Grenzen und weitere sinnvolle Prüfungen

Dies ist ein kompletter Basisdurchlauf pro Spiel, keine Garantie für jede mögliche Kombination. Browser-Ansichten ersetzen keinen längeren Test auf echtem iPhone/Android. Besonders sinnvoll bleiben Langzeitpartien von Snake/Flipper über instabile Mobilfunkverbindungen und eine redaktionelle Durchsicht des gesamten Fragenbestands. Die gefundenen, reproduzierbaren Fehler dieses Durchlaufs wurden direkt korrigiert.
