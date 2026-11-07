import type { Question } from "./types.ts";

// Individually authored German prompts. No cross-product or machine translation.
const rows = (text: string) => text.trim().split("\n").map(x => x.trim()).filter(Boolean);
function questions(game: Question["game"], category: string, text: string): Question[] {
 return rows(text).map((prompt,index)=>({id:`de26-${game}-${category.toLowerCase()}-${index+1}`,game,category,prompt}));
}
export const editorialChoices: Question[] = rows(`
Gemeinsam ein neues Rezept ausprobieren|Das Lieblingsgericht perfektionieren
Eine Nacht im Baumhaus|Eine Nacht auf einem Hausboot
Ein Date bei Sonnenaufgang|Ein Date unter Sternen
Zusammen einen Tanzkurs besuchen|Zusammen einen Töpferkurs besuchen
Ein Wochenende am See|Ein Wochenende in den Bergen
Ein fest geplantes Date|Ein Date mit Überraschungsziel
Ein handgeschriebener Brief|Eine selbst zusammengestellte Playlist
Ein gemeinsames Fotoalbum|Ein gemeinsames Reisetagebuch
Im Urlaub früh auf Entdeckung gehen|Im Urlaub lange frühstücken
Ein kleines Konzert im Club|Ein großes Konzert im Stadion
Ein Abend mit Brettspielen|Ein Abend mit Videospielen
Zusammen ein Möbelstück bauen|Zusammen ein Zimmer streichen
Ein Film, den ihr beide kennt|Ein Film, über den ihr nichts wisst
Ein gemeinsames Hobby vertiefen|Ein neues Hobby ausprobieren
Zusammen zum Flohmarkt|Zusammen ins Museum
Ein Picknick im Park|Ein Abendessen auf dem Balkon
Eine Reise mit dem Nachtzug|Eine Reise mit dem Camper
Im Urlaub eine Stadt gründlich erkunden|Im Urlaub mehrere Orte besuchen
Ein Kochabend nur für euch|Ein Kochabend mit Freunden
Ein kleiner Geburtstagsausflug|Eine kleine Geburtstagsfeier zu Hause
Ein gemeinsames Jahresziel|Jeden Monat eine neue Idee
Ein Date ohne Handy|Ein Date mit lustiger Foto-Challenge
Ein Frühstück im Bett|Ein Frühstück im Lieblingscafé
Zusammen einen Podcast hören|Zusammen ein Hörbuch hören
Eine Wohnung mitten in der Stadt|Ein kleines Haus am Stadtrand
Den nächsten Urlaub lange planen|Spontan ein freies Wochenende nutzen
Ein Besuch im Tierpark|Ein Besuch im botanischen Garten
Eine gemeinsame Massage|Ein gemeinsamer Saunatag
Ein entspannter Spaziergang|Eine sportliche Radtour
Einen Kuchen zusammen backen|Ein Drei-Gänge-Menü zusammen kochen
Ein persönliches Geschenk selbst machen|Ein lange gewünschtes Geschenk kaufen
Einen besonderen Tag groß feiern|Mehrere kleine Alltagsmomente feiern
Ein Abend im Theater|Ein Abend im Kino
Eine Wanderung mit Aussicht|Eine Bootsfahrt mit Badestopp
Ein gemeinsamer Kalender|Eine gemeinsame Liste für spontane Ideen
Eine Überraschungsparty bekommen|Vorher an der Planung beteiligt sein
Einen Spieleabend veranstalten|Bei einem Spieleabend zu Gast sein
Auf Reisen ein gemütliches Hotel|Auf Reisen eine eigene Ferienwohnung
Zusammen einen Garten pflegen|Zusammen ein Aquarium pflegen
Ein Wochenende mit viel Programm|Ein Wochenende mit nur einem festen Plan
Beim Date etwas Neues lernen|Beim Date einfach entspannen
Eine lange Umarmung zur Begrüßung|Ein langer Kuss zum Abschied
Einen Konflikt nach kurzer Pause besprechen|Einen Konflikt sofort ruhig ansprechen
Unterstützung durch Zuhören|Unterstützung durch praktische Hilfe
Eine feste gemeinsame Abendroutine|Jeden Abend spontan entscheiden
Jahrestage am ursprünglichen Ort feiern|Zum Jahrestag einen neuen Ort entdecken
Gemeinsam einen Escape Room lösen|Gemeinsam ein Krimidinner spielen
Ein Weihnachtsmarkt-Date|Ein Sommerfest-Date
Ein Date im Regen mit warmem Tee danach|Ein Date in der Sonne mit Eis danach
Einen Sternenhimmel beobachten|Ein Gewitter vom Fenster aus beobachten
Im Urlaub regionale Gerichte probieren|Im Urlaub vertraute Lieblingsgerichte suchen
Am Wochenende gemeinsam aufräumen|Unter der Woche kleine Aufgaben verteilen
Ein gemeinsames Sparziel für Reisen|Ein gemeinsames Sparziel fürs Zuhause
Ein festes Lieblingsrestaurant|Jeden Monat ein anderes Restaurant
Einen Hund ausführen|Eine Katze betreuen
Ein Abend am Lagerfeuer|Ein Abend vor dem Kamin
Einen Wunschzettel austauschen|Geschenke ohne Hinweise aussuchen
Zusammen ein Puzzle legen|Zusammen ein Modell bauen
Beim Wandern eine Hütte als Ziel|Beim Wandern einen See als Ziel
Eine Reise im Frühling|Eine Reise im Herbst
Zusammen Karaoke singen|Zusammen beim Pubquiz mitmachen
Auf dem Sofa kuscheln|Beim Spaziergang Händchen halten
Eine gemeinsame Tradition bewahren|Eine neue gemeinsame Tradition beginnen
Ein fest reservierter Date-Abend|Mehrere spontane kurze Dates
Ein langer Videoanruf|Mehrere kurze Sprachnachrichten
Ein ruhiger Ausflug zu zweit|Ein Ausflug mit einem befreundeten Paar
Einen Urlaub am selben Ort verbringen|Während des Urlaubs den Ort wechseln
Einen Lieblingsplatz für euch entdecken|Dem anderen den eigenen Lieblingsplatz zeigen
Ein Foto von einem besonderen Moment|Eine kleine Erinnerung zum Mitnehmen
Ein Date mit gemeinsamem Rätsel|Ein Date mit gemeinsamem Kunstprojekt
Zusammen früh schlafen gehen|Zusammen bis spät reden
Ein gemeinsamer Sportkurs|Ein gemeinsamer Sprachkurs
Eine schöne Aussicht vom Berg|Eine schöne Aussicht vom Meer
Beim Date das Essen teilen|Beim Date zwei verschiedene Gerichte bestellen
Die erste Reihe beim Konzert|Ein entspannter Platz weiter hinten
Für einen Abend schick anziehen|Für einen Abend gemütliche Sachen anziehen
Ein Wochenende ohne Termine|Ein Wochenende mit einem lang ersehnten Ereignis
Ein gemeinsames Frühstück unter der Woche|Ein gemeinsames Mittagessen am Wochenende
Die Wohnung mit Pflanzen gestalten|Die Wohnung mit eigenen Fotos gestalten
Einen Überraschungsbesuch bekommen|Vor einem Besuch genug Vorbereitungszeit haben
Einen Ausflug mit dem Fahrrad planen|Einen Ausflug mit der Bahn planen
Einen Filmabend nach Genre auswählen|Einen Filmabend nach Schauspielern auswählen
Im Urlaub ein Abenteuer wagen|Im Urlaub bewusst zur Ruhe kommen
Einen Kuchen für Freunde backen|Ein Abendessen für Freunde kochen
Zusammen ein Sachbuch besprechen|Zusammen einen Roman besprechen
Einen Sonnenuntergang am Wasser|Einen Sonnenuntergang über der Stadt
Ein Date mit gemeinsamem Einkauf fürs Abendessen|Ein Date mit einem fertig gepackten Picknick
Eine lustige gemeinsame Erinnerung erzählen|Eine bisher unbekannte Geschichte erzählen
Ein Lieblingslied zusammen hören|Ein neues Album zusammen entdecken
Einen Abend ohne Hintergrundgeräusche|Einen Abend mit leiser Musik
Ein Museum mit Führung|Ein Museum im eigenen Tempo
Ein gemeinsames Wochenziel aufschreiben|Am Wochenende gemeinsam zurückblicken
Ein Gericht mit vielen Gewürzen|Ein Gericht mit wenigen guten Zutaten
Einen freien Tag zu Hause genießen|Einen freien Tag draußen verbringen
Zusammen den Keller entrümpeln|Zusammen alte Fotos sortieren
Ein Date mit Minigolf|Ein Date mit Bowling
Eine Fahrt im Riesenrad|Eine Fahrt auf der Achterbahn
Im Sommer im See schwimmen|Im Sommer im Freibad schwimmen
Ein gemeinsamer Morgenlauf|Ein gemeinsamer Abendspaziergang
Ein Abenteuer verschenken|Einen gemütlichen Tag verschenken
`).map((line,index)=>{const [optionA,optionB]=line.split("|");return {id:`de26-choice-${index+1}`,game:"this-or-that",category:"Date",prompt:"Was würdest du lieber wählen?",optionA,optionB};});

// {person} is resolved explicitly, never by replacing German pronouns heuristically.
export const editorialKnowTemplates = rows(`
Welches Gericht würde {person} nach einem anstrengenden Tag bestellen?
Welches kleine Geschenk würde {person} gerade besonders freuen?
Welche Hausarbeit würde {person} am liebsten dauerhaft abgeben?
Welchen Ausflug würde {person} für einen freien Sonntag wählen?
Bei welchem Lied würde {person} sofort mitsingen?
Was würde {person} mit einem geschenkten freien Nachmittag anfangen?
Welches Reiseziel möchte {person} schon länger besuchen?
Welche Gewohnheit möchte {person} gerade verändern?
Was hilft {person} nach einem Streit, wieder Nähe zuzulassen?
Welches Kompliment bedeutet {person} besonders viel?
Welche gemeinsame Erinnerung würde {person} gern noch einmal erleben?
Welche Fähigkeit würde {person} gern ohne langes Üben beherrschen?
Welches Spiel würde {person} für einen Abend zu zweit aussuchen?
Worauf achtet {person} zuerst, wenn eine Ferienwohnung ausgesucht wird?
Was braucht {person}, um sich an einem neuen Ort wohlzufühlen?
Welche Kleinigkeit kann {person} morgens die Laune verderben?
Wie würde {person} einen persönlichen Erfolg am liebsten feiern?
Welche Süßigkeit würde {person} im Kino wählen?
Wen würde {person} bei einer schwierigen Entscheidung zuerst um Rat fragen?
Was vergisst {person} beim Packen am ehesten?
Welches Tier würde {person} gern einmal in freier Natur sehen?
Welche Serie würde {person} noch einmal von vorne schauen?
Welches Kindheitsessen würde {person} gern wieder probieren?
Was würde {person} an einem verregneten Urlaubstag unternehmen?
Wofür würde {person} eher Geld ausgeben: gutes Essen, Technik oder Erlebnisse?
Welche Musik würde {person} auf einer langen Autofahrt einschalten?
Wie viel Planung braucht {person}, bevor eine Reise entspannt beginnen kann?
Welche Aktivität lehnt {person} eher ab, obwohl viele sie mögen?
Was findet {person} an unserem Alltag besonders schön?
Welche gemeinsame Tradition würde {person} gern beibehalten?
Welche Grenze ist {person} im Umgang mit anderen wichtig?
Was motiviert {person}, eine schwierige Aufgabe zu beginnen?
Was würde {person} beim Frühstück niemals weglassen?
Welches Kleidungsstück trägt {person} besonders gern?
Welcher Duft erinnert {person} an etwas Schönes?
Wobei verliert {person} leicht das Zeitgefühl?
Welchen Beruf würde {person} einen Tag lang ausprobieren?
Was würde {person} gern öfter mit Freunden unternehmen?
Was kann {person} auch nach Jahren noch zum Lachen bringen?
Bei welcher Sache ist {person} überraschend geduldig?
Welche Aufgabe schiebt {person} gern bis zum letzten Moment auf?
Welche Art von Überraschung mag {person} besonders?
Welchen Film würde {person} für einen gemütlichen Abend wählen?
Was würde {person} an der eigenen Wohnung als Erstes verändern?
Welche Sache würde {person} auf einer langen Zugfahrt beschäftigen?
Was hilft {person}, vor einem wichtigen Termin ruhig zu werden?
Welche Nachricht würde {person} an einem stressigen Tag guttun?
Welches gemeinsame Foto würde {person} einrahmen?
Welchen Ort aus der Kindheit würde {person} gern zeigen?
Was würde {person} auf einem Wochenmarkt zuerst kaufen?
Welche Jahreszeit passt am besten zu den Lieblingsaktivitäten von {person}?
Was ist {person} bei einem Restaurantbesuch wichtiger als der Preis?
Welche neue Sache würde {person} gern mit mir ausprobieren?
Woran merkt man zuerst, dass {person} müde ist?
Welche Bitte fällt {person} besonders schwer?
Welche Art von Humor mag {person} am liebsten?
Welchen Gegenstand würde {person} ungern verleihen?
Welches Thema könnte {person} stundenlang erklären?
Was braucht {person} nach einem langen Tag unter Menschen?
Welchen Snack würde {person} für ein Picknick einpacken?
Worauf freut sich {person} in den nächsten Wochen am meisten?
Welche Entscheidung aus dem letzten Jahr würde {person} wieder so treffen?
Womit könnte man {person} spontan eine Freude machen?
Welche Kleinigkeit fällt {person} in fremden Wohnungen sofort auf?
Was würde {person} bei einer Reise lieber vermeiden?
Welches Essen würde {person} gern selbst kochen lernen?
Was würde {person} tun, wenn ein geplanter Ausflug kurzfristig ausfällt?
Welche Eigenschaft schätzt {person} an engen Freunden besonders?
Welche Form von Unterstützung erwartet {person} bei einem Problem?
Welches persönliche Projekt möchte {person} irgendwann angehen?
Welche Tätigkeit gibt {person} schnell neue Energie?
Wie würde {person} einen völlig freien Geburtstag verbringen?
Was würde {person} bei einem Umzug zuerst auspacken?
Was würde {person} für einen gemütlichen Abend vorbereiten?
Welches Brettspiel würde {person} gern lernen?
Welches Konzert würde {person} sofort besuchen, wenn es Tickets gäbe?
Welche alltägliche Regel würde {person} gern abschaffen?
Was macht {person} lieber allein als gemeinsam?
Welche Art von Erinnerungsstück hebt {person} auf?
Welche neue Gewohnheit würde {person} gern mit mir beginnen?
`);
export const editorialKnow = editorialKnowTemplates.map((template,index):Question=>({id:`de26-know-${index+1}`,game:"do-you-know-me",category:"Us",prompt:template}));
export function editorialGuess(id: string, name: string) { const n=Number(id.replace('de26-know-',''))-1; return editorialKnowTemplates[n]?.replaceAll('{person}',name); }

export const editorialTalk = [
 ...questions('deep-talk','Us',`
Wann hast du dich mir zuletzt besonders nah gefühlt?
Welche kleine Geste von mir macht für dich einen großen Unterschied?
Was sollten wir im Alltag wieder häufiger gemeinsam tun?
Woran merkst du, dass wir als Team gut funktionieren?
Bei welchem Thema verstehen wir uns heute besser als früher?
Welche gemeinsame Erinnerung erzählst du besonders gern?
Was haben wir zusammen gelernt, das keiner allein gelernt hätte?
Welche Art von gemeinsamer Zeit kommt gerade zu kurz?
Wie möchtest du angesprochen werden, wenn ich mir Sorgen um uns mache?
Was bedeutet Verlässlichkeit für dich ganz konkret?
Wann fühlst du dich von mir wirklich gesehen?
Welche unserer Unterschiede bereichert dein Leben?
Was wäre für dich ein kleiner, realistischer Schritt zu mehr Nähe?
Wie können wir einander Freiraum geben, ohne uns aus dem Blick zu verlieren?
Welche Gewohnheit von uns möchtest du gern bewahren?
Was macht ein gutes Gespräch zwischen uns aus?
Wobei möchtest du öfter um meine Hilfe bitten können?
Wie können wir Erfolge feiern, die von außen unscheinbar wirken?
Was würdest du gern über meinen Alltag besser verstehen?
Worauf bist du stolz, wenn du an uns denkst?
Welche Erwartung an Beziehungen hast du durch uns verändert?
Wie sieht ein Abend aus, an dem du dich mit mir vollkommen wohlfühlst?
Welches gemeinsame Erlebnis hat dich überrascht?
Was sollten wir uns sagen, bevor Ärger sich aufstaut?
Wie können wir Zuneigung zeigen, wenn einer von uns wenig Energie hat?
Welche Sache sollten wir öfter gemeinsam entscheiden?
Wann hat dir mein Vertrauen in dich geholfen?
Was möchtest du in unserer Beziehung nie als selbstverständlich behandeln?
Welche Frage hast du mir schon länger stellen wollen?
Wie können wir nach einer schwierigen Woche wieder zueinander finden?
`),
 ...questions('deep-talk','Future',`
Welche gemeinsame Entscheidung möchtest du in Ruhe vorbereiten?
Wie soll sich unser Alltag in fünf Jahren anfühlen?
Was darf sich verändern, und was soll unbedingt bleiben?
Welche Tradition möchtest du mit mir neu beginnen?
Welches gemeinsame Ziel ist uns beiden wichtig, aber noch zu vage?
Was wäre ein Zuhause, in dem wir beide gut leben könnten?
Wie möchtest du später auf diese Phase unseres Lebens zurückblicken?
Welche Sorge über die Zukunft möchtest du mit mir teilen?
Wie können wir persönliche Träume verfolgen und uns trotzdem unterstützen?
Was möchtest du lernen, das unser gemeinsames Leben bereichern könnte?
Wie stellen wir sicher, dass große Pläne auch Platz für Erholung lassen?
Welche Erfahrung möchtest du lieber machen als etwas Teures besitzen?
Wofür würdest du dir im nächsten Jahr bewusst mehr Zeit freihalten?
Wie würden wir merken, dass ein gemeinsamer Plan nicht mehr zu uns passt?
Welche Rolle sollen Freunde in unserem zukünftigen Alltag spielen?
Was möchtest du im Alter noch regelmäßig mit mir tun?
Welchen Ort würdest du gern für längere Zeit gemeinsam kennenlernen?
Welche Entscheidung würden wir treffen, wenn wir weniger Angst vor Fehlern hätten?
Wie können wir einander bei beruflichen Veränderungen Rückhalt geben?
Welchen kleinen Zukunftswunsch könnten wir schon diesen Monat angehen?
`),
 ...questions('deep-talk','Dreams',`
Welchen Wunsch hast du lange zurückgestellt, obwohl er dir wichtig ist?
Was würdest du gern ausprobieren, ohne darin gut sein zu müssen?
Welcher Traum aus deiner Kindheit bedeutet dir heute noch etwas?
Woran würdest du merken, dass du ein erfülltes Leben führst?
Was möchtest du erschaffen, das ganz von dir stammt?
Welche Fähigkeit bewunderst du bei anderen und möchtest sie selbst lernen?
Wofür würdest du ein Jahr lang regelmäßig üben?
Welches Abenteuer reizt dich, obwohl es dich auch verunsichert?
Welche Form von Freiheit fehlt dir gerade am meisten?
Was würdest du tun, wenn Anerkennung von außen keine Rolle spielte?
Welchen Wunsch traust du dich selten laut auszusprechen?
Welche Veränderung würde deinen Alltag leichter machen?
Welchen Menschen würdest du gern einmal persönlich kennenlernen und warum?
Was möchtest du erlebt haben, ohne es fotografieren zu müssen?
Welches Projekt würdest du beginnen, wenn dir jemand den ersten Schritt erleichtert?
Was bedeutet Erfolg für dich heute im Unterschied zu früher?
Welche Reise würde dich persönlich verändern können?
Wann hast du zuletzt etwas nur aus Neugier gemacht?
Welchen Traum möchtest du lieber allein verfolgen und welchen gemeinsam?
Was wäre ein mutiger, aber machbarer nächster Schritt für dich?
`),
 ...questions('deep-talk','Memories',`
Welche Erinnerung aus deiner Kindheit gibt dir bis heute Geborgenheit?
Welcher Mensch hat dir etwas Wichtiges beigebracht, ohne es zu wissen?
An welchen Geruch aus deiner Kindheit erinnerst du dich sofort?
Welche Entscheidung von früher verstehst du heute mit mehr Mitgefühl?
Welchen gewöhnlichen Tag würdest du gern noch einmal erleben?
Wann warst du zum ersten Mal wirklich stolz auf dich?
Welche Freundschaft hat deine Sicht auf die Welt geprägt?
Welche Familientradition möchtest du weiterführen und welche nicht?
Was hast du früher für selbstverständlich gehalten, das du heute schätzt?
Welcher Abschied hat dich stärker verändert, als du erwartet hattest?
Welche Erinnerung verbindest du mit einem bestimmten Lied?
Welche Geschichte aus deinem Leben kennt kaum jemand?
Wann hat dich jemand unterstützt, obwohl du nicht darum gebeten hattest?
Welcher kleine Zufall hat dein Leben in eine andere Richtung gelenkt?
Welchen Rat hättest du deinem jüngeren Ich gern gegeben?
Welche gemeinsame Erinnerung möchtest du vor dem Vergessen bewahren?
Welche Schwierigkeit hat dir gezeigt, dass du mehr kannst als gedacht?
Was vermisst du an einer früheren Lebensphase und was überhaupt nicht?
Welches Erlebnis hat dein Vertrauen in andere Menschen gestärkt?
Welche Erinnerung würde mich etwas Neues über dich verstehen lassen?
`),
 ...questions('deep-talk','Vulnerability',`
Woran merkst du, dass du gerade mehr Unterstützung brauchst?
Was fällt dir leichter zu geben als anzunehmen?
Welche Sorge wird kleiner, wenn du sie laut aussprichst?
Wie kann ich erkennen, dass du eine Pause brauchst?
Was hilft dir, dich nach einem Fehler nicht nur darüber zu definieren?
Welche Grenze möchtest du künftig klarer aussprechen?
Wann fühlst du dich unter Druck, stark wirken zu müssen?
Was brauchst du, damit eine Entschuldigung bei dir ankommt?
Welche Art von Kritik kannst du gut annehmen und welche trifft dich besonders?
Was möchtest du mir sagen können, ohne gleich eine Lösung finden zu müssen?
Wie kannst du mir zeigen, dass etwas für dich schwerer ist, als es aussieht?
Was hilft dir, dich nach einer Enttäuschung wieder zu öffnen?
Welche Unsicherheit möchtest du mit mehr Freundlichkeit betrachten?
Wie sieht Trost aus, der dir wirklich hilft?
Wann fühlst du dich allein, obwohl Menschen um dich sind?
Welche Erwartung an dich selbst würdest du gern loslassen?
Was macht es dir leichter, um Hilfe zu bitten?
Woran merkst du, dass du dich in einem Gespräch sicher fühlst?
Was möchtest du nicht erklären müssen, sondern einfach ernst genommen wissen?
Wie können wir schwierige Themen ansprechen, ohne einander zu überfordern?
`),
 ...questions('deep-talk','Values',`
Welche Überzeugung hast du in den letzten Jahren verändert?
Was bedeutet Fairness für dich, wenn unsere Möglichkeiten unterschiedlich sind?
Welche Grenze würdest du auch für viel Geld nicht überschreiten?
Wann ist Ehrlichkeit für dich wichtiger als Harmonie?
Welche Verantwortung möchtest du bewusst übernehmen?
Was bedeutet für dich ein gutes Leben jenseits von Leistung?
Wie gehst du damit um, wenn zwei wichtige Werte miteinander kollidieren?
Welche Eigenschaft möchtest du in dir stärker entwickeln?
Was bewunderst du an Menschen, die ganz anders leben als du?
Welche Rolle soll Geld in deinem Leben spielen?
Wann ist ein Kompromiss fair und wann gibst du zu viel von dir auf?
Wie möchtest du mit Menschen umgehen, deren Meinung du nicht teilst?
Was bedeutet Loyalität, wenn du einem Freund widersprechen musst?
Welche Entscheidung möchtest du später vor dir selbst vertreten können?
Wofür möchtest du im Alltag ein besseres Beispiel sein?
Was sollten wir bei gemeinsamen Entscheidungen nie übersehen?
Was bedeutet Großzügigkeit für dich, wenn Geld knapp ist?
Wann ist es richtig, eine eigene Meinung noch einmal zu überprüfen?
Was willst du bewahren, auch wenn dein Leben sich stark verändert?
Welche Art von Mensch möchtest du für andere sein?
`),
];
export const editorialWords = [
 ...questions('drawing-word','Tiere',`Faultier\nWaschbär\nEichhörnchen\nChamäleon auf einem Ast\nPinguin mit Schal\nKatze im Karton\nHund beim Baden\nEule auf einem Buch\nSchlafender Fuchs\nKrake mit Regenschirm\nBiber am Staudamm\nIgel im Laub\nPelikan mit Fisch\nSchnecke auf einem Blatt\nFliegender Fisch\nGiraffe am Fenster\nOtter auf dem Rücken\nEisvogel\nLibelle am Teich\nKänguru mit Einkaufstasche`),
 ...questions('drawing-word','Dates',`Picknick am See\nKinoabend\nTanz im Regen\nFrühstück im Bett\nGemeinsames Kochen\nSternenhimmel beobachten\nHändchenhalten\nBootsfahrt\nSchneemann bauen\nPärchen auf dem Riesenrad\nKuss am Bahnhof\nSpaziergang mit Hund\nZelten im Wald\nKaraoke zu zweit\nKuchen backen\nSonnenuntergang am Strand\nFotos im Automaten\nMinigolf\nSchlittschuhlaufen\nKerzen auf dem Esstisch`),
 ...questions('drawing-word','Knifflig',`Ein schmelzender Schneemann\nEin Roboter beim Blumenpflücken\nEin Haus auf dem Rücken einer Schildkröte\nEine Katze als Kapitän\nEin Fahrrad mit einem platten Reifen\nEin Regenschirm im Sturm\nEin Astronaut im Supermarkt\nEin Drache beim Zähneputzen\nEin Leuchtturm auf einer kleinen Insel\nEin Baumhaus mit Seilbrücke\nEin Karussell aus Teetassen\nEin Pirat beim Kuchenbacken\nEin Bücherregal als Geheimtür\nEine Stadt in einer Schneekugel\nEin Frosch im Fitnessstudio\nEin fliegender Teppich über Dächern\nEin Fuchs als Fotograf\nEin schiefes Kartenhaus\nEin Schachspiel unter Wasser\nEin überfüllter Picknickkorb\nEine Maus mit riesigem Käse\nEin Hamster im Raumschiff\nEin Elefant auf Rollschuhen\nEine verwunschene Bibliothek\nEine Sandburg mit Zugbrücke\nEin Tintenfisch als Schlagzeuger\nEin Bär am Honigautomaten\nEin Spiegel mit einem anderen Gesicht\nEin Berg aus Eiscreme\nEine Pflanze mit Wanderschuhen`),
];
