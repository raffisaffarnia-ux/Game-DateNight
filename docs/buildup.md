# BuildUp

BuildUp ist über `/games/BuildUp` erreichbar. Es hat keinen Eintrag in der öffentlichen Spieleliste und im Glücksrad. Die URL ist ungelistet. Wer sie kennt, kann die Einstiegsseite öffnen.

## Spielen

Eine Person eröffnet über den Direktlink ein Atelier und teilt den angezeigten Einladungslink oder Code. Die zweite Person tritt über denselben BuildUp-Link bei. Der Host konfiguriert Same Mind oder Know Your Partner, drei, fünf oder acht Runden und einen Themenmix. Beide sehen die Konfiguration. Im Vorhersagemodus baut jede Person zuerst ihre eigene Kreation und anschließend eine Vorhersage für die andere Person.

Der Vergleich zählt identische Optionskennungen. Der Gesamtwert gewichtet die Anzahl tatsächlicher Entscheidungen. Im Vorhersagemodus werden beide Richtungen zusätzlich einzeln ausgewertet. Neue Partien bevorzugen andere Themen als die vorherige Partie. Bei einer kleinen ausdrücklich ausgewählten Themenmenge können Themen erneut erscheinen.

## Architektur

Die Route nutzt die bestehenden Supabase-Identitäten, privaten Räume, Mitgliedschaften, Presence und den vorhandenen `useGameState`-Adapter. Die öffentlichen Fortschritte liegen als `buildup`-Eintrag in `game_states`. Entwürfe liegen in `private.buildup_entries`, ohne direkten Clientzugriff. `buildup_mine` liefert ausschließlich die Auswahl der eigenen Identität. `buildup_move` serialisiert Aktionen über die Raumzeile, prüft Mitgliedschaft, ursprüngliche Teilnehmer, Phase, Session, Runde und gültige Optionen. Alte oder doppelte Finalisierungen bewirken keinen zweiten Übergang.

Die Aufdeckung entsteht atomar, wenn beide finalisiert haben. Nach einem Reload werden bestätigte Entwürfe geladen. Eine noch unbestätigte Auswahl bleibt lokal. Die nächste Runde beginnt erst nach beiden Bestätigungen. Das X beendet BuildUp für beide und führt zurück in die bestehende Raumansicht.

Die drei additiven Migrationen sind `20261113194000_buildup.sql`, `20261114121500_buildup_sync.sql` und `20261114132500_buildup_images_reveal.sql`.

## Themen und Darstellung erweitern

`src/games/buildup/topics.ts` enthält die 19 Themen und ihre Schritte. Optionspositionen bilden persistente Kennungen. Bestehende Optionen deshalb nicht umsortieren. Neue Themen und geänderte Optionszahlen müssen zusätzlich mit einer additiven Migration in den serverseitigen Validierungskatalog aufgenommen werden.

`art.tsx` setzt Outfits aus SVG-Ebenen zusammen. `scenes.tsx` enthält Zimmer, Pizza und Auto. Die übrigen Themen verwenden Auswahlkarten und eine Zusammenstellung der tatsächlich gewählten Inhalte. `illustrations.tsx` ordnet Optionen gezeichnete Motive zu. Lokale Reisefotos und ihre Quellen stehen in `assets.ts`. Die Schriftarten und Profilnavigation stammen aus DateNight.io.

## Optionale Fotos

Für optionale Pexels-Reisefotos in Vercel die serverseitige Variable `PEXELS_API_KEY` eintragen und erneut deployen. Einen Schlüssel gibt es über [Pexels](https://www.pexels.com/api/). Die authentifizierte Start-Route verwendet eine feste Liste präziser Suchbegriffe, einen Tagescache und kurze Zeitlimits. Die Bildauswahl wird vor dem Start im gemeinsamen Spielzustand eingefroren. Fehlende Fotos verwenden lokale Motive. Die Bildnachweise verlinken Fotograf und Pexels.

Die Pexels-Anbindung ist ohne Schlüssel inaktiv und wurde ohne ein kostenpflichtiges Konto vorbereitet. Suchergebnisse können redaktionelle Bildprüfung benötigen. Die lokalen Reisefotos kommen von Unsplash, ihre Quellenkennungen sind im Asset-Katalog hinterlegt.

KI-Bilder werden derzeit nicht erzeugt. Ein späterer Generator kann die gespeicherten Optionskennungen über den Themenkatalog in Beschreibungen auflösen und eine zusätzliche Ergebnisdarstellung liefern. Er benötigt eine gesonderte serverseitige Anbieterintegration und bewusst eingerichtete Zugangsdaten.

## Prüfung

Die Datenbanktests prüfen beide Modi über mehrere Runden, geheime Antworten, ungültige Optionen, fremde Identitäten, doppelte und verspätete Aktionen, Bildquellen, Neustart und das gemeinsame Weitergehen. Die Gesamtberechnung ist auch für verschieden lange Runden getestet. Browserprüfungen verwenden zwei getrennte Profile und mobile Viewports.

