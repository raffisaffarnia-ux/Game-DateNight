export type Topic = {
  enabled: boolean;
  visualizationType: "layered" | "story" | "moodboard";
  availableModes: readonly ["same", "partner"];
  id: string;
  title: string;
  category: string;
  intro: string;
  icon: string;
  steps: { label: string; options: string[] }[];
};
function topic(
  id: string,
  title: string,
  category: string,
  intro: string,
  icon: string,
  choices: string[],
): Topic {
  const steps = choices.map((choice) => {
    const [label, options] = choice.split(":");
    return { label, options: options.split("/") };
  });
  return {
    id,
    title,
    category,
    intro,
    icon,
    steps,
    enabled: true,
    availableModes: ["same", "partner"],
    visualizationType: ["ball", "room", "pizza", "car"].includes(id)
      ? "layered"
      : ["date", "disaster"].includes(id)
        ? "story"
        : "moodboard",
  };
}
// Option indices are persistent identifiers. Append options without reordering existing entries.
export const topics = [
  topic(
    "ball",
    "The Perfect Ball Outfit",
    "Creative",
    "Stell deinen Look für den Ball zusammen.",
    "🪩",
    [
      "Sakko:Klassisch schwarz/Mitternachtsblau/Bordeauxrot/Cremeweiß",
      "Hemd:Weiß/Schwarz/Hellblau/Rosé",
      "Krawatte:Schwarze Seide/Bordeauxrot/Marineblau/Offener Kragen",
      "Hose:Schwarz/Marineblau/Creme/Anthrazit",
      "Schuhe:Schwarze Oxfords/Braune Lederschuhe/Schwarze Loafer/Weiße Sneaker",
    ],
  ),
  topic(
    "room",
    "Dream Room",
    "Lifestyle",
    "Gestalte einen Raum, in dem du gern aufwachst.",
    "🛏️",
    [
      "Raumstil:Modern/Gemütlich/Minimalistisch/Luxuriös",
      "Bett:Podestbett/Holzbett/Himmelbett/Futon",
      "Palette:Warmes Beige/Schwarzweiß/Pastell/Erdfarben",
      "Licht:LED-Band/Tischlampen/Pendelleuchte/Lichterkette",
      "Extra:Balkon/Gaming-Ecke/Lesesessel/Ankleide",
    ],
  ),
  topic(
    "vacation",
    "Dream Vacation",
    "Lifestyle",
    "Pack deine fünf liebsten Urlaubsmomente ein.",
    "🌴",
    [
      "Reiseziel:Tropeninsel/Großstadt/Bergwelt/Mittelmeerküste",
      "Unterkunft:Strandresort/Boutiquehotel/Berghütte/Villa",
      "Anreise:Flugzeug/Roadtrip/Zug/Schiff",
      "Aktivität:Abenteuer/Stadtbummel/Entspannen/Wassersport",
      "Abend:Dinner am Hafen/Sonnenuntergang am Strand/Tanzen/Lesen im Bett",
    ],
  ),
  topic(
    "date",
    "Perfect Date",
    "Romance",
    "Plane den Abend, an den du dich noch lange erinnerst.",
    "🌙",
    [
      "Ort:Strand/Dachterrasse/Zuhause/Waldlichtung",
      "Look:Elegant/Lässig/Kuschelig/Extravagant",
      "Essen:Italienisch/Asiatisch/Streetfood/Selbst gekocht",
      "Aktivität:Kino/Kletterpark/Spaziergang/Spieleabend",
      "Ausklang:Sterne zählen/Dessert teilen/Tanzen/Sonnenaufgang",
    ],
  ),
  topic(
    "disaster",
    "Worst Date Ever",
    "Funny",
    "Wie schief kann ein einziges Date gehen?",
    "🌧️",
    [
      "Ort:Familienessen/Voller Schnellimbiss/Geisterhaus/Großraumbüro",
      "Look:Schlafanzug/Dinokostüm/Frack/Zwei linke Schuhe",
      "Essen:Viel zu scharf/Winzige Portion/Klecksende Soße/Mysteriöse Suppe",
      "Aktivität:Karaoke-Panne/Verpatzter Zaubertrick/Film ohne Ton/Peinliches Doppeldate",
      "Finale:Schlüssel verloren/Wolkenbruch/Zug verpasst/Mikro war an",
    ],
  ),
  topic(
    "house",
    "Dream House",
    "Lifestyle",
    "Entwirf dein Zuhause vom Dach bis zum Garten.",
    "🏡",
    [
      "Baustil:Holzhaus/Loft/Stadtvilla/Fachwerkhaus",
      "Umgebung:See/Wald/Altstadt/Blumenwiese",
      "Garten:Obstwiese/Blumenhof/Dachgarten/Kräutergarten",
      "Pool:Naturteich/Infinitypool/Whirlpool/Schwimmteich",
      "Wohnzimmer:Kaminzimmer/Bibliothek/Heimkino/Musikzimmer",
    ],
  ),
  topic(
    "pizza",
    "Perfect Pizza",
    "Creative",
    "Belege ein Stück Italien ganz nach deinem Geschmack.",
    "🍕",
    [
      "Teig:Dünn und knusprig/Dicker Rand/Vollkorn/Sauerteig",
      "Sauce:Tomate/Pesto/Bianca/BBQ",
      "Käse:Mozzarella/Gorgonzola/Parmesan/Veganer Käse",
      "Belag:Pilze/Salami/Artischocken/Paprika",
      "Extra:Basilikum/Chiliöl/Rucola/Oliven",
    ],
  ),
  topic(
    "car",
    "Dream Car",
    "Lifestyle",
    "Bau das Auto für deine nächste Ausfahrt.",
    "🚘",
    [
      "Typ:Cabrio/Kombi/Coupé/SUV",
      "Lack:Kirschrot/Salbeigrün/Graphit/Nachtblau",
      "Felgen:Speichen/Chrom/Mattschwarz/Stahl",
      "Innenraum:Leder/Stoff/Velours/Alcantara",
      "Extra:Panoramadach/Soundsystem/Sitzheizung/Dachträger",
    ],
  ),
  topic(
    "festival",
    "Festival Fit",
    "Creative",
    "Stell deinen Look für die erste Reihe zusammen.",
    "🎸",
    [
      "Oberteil:Bandshirt/Glitzertop/Jeansjacke/Leinenhemd",
      "Hose:Shorts/Cargo/Schlaghose/Latzhose",
      "Schuhe:Stiefel/Sneaker/Sandalen/Plateauschuhe",
      "Zubehör:Sonnenbrille/Bauchtasche/Blumenkranz/Fächer",
      "Frisur:Zöpfe/Offene Wellen/Bunter Iro/Dutt",
    ],
  ),
  topic(
    "wedding",
    "Dream Wedding",
    "Romance",
    "Entwirf einen Tag, der ganz euch gehört.",
    "💐",
    [
      "Ort:Weingut/Strand/Bergalm/Schloss",
      "Kleidung:Klassisch/Boho/Bunt/Leinen",
      "Essen:Festmenü/Grillbuffet/Foodtrucks/Vegetarisches Buffet",
      "Musik:Jazztrio/DJ/Akustikduo/Streichquartett",
      "Dekoration:Wildblumen/Kerzen/Laternen/Trockenblumen",
    ],
  ),
  topic(
    "sunday",
    "Perfect Sunday",
    "Lifestyle",
    "Füll einen freien Sonntag mit Lieblingsmomenten.",
    "☕",
    [
      "Aufstehen:Bei Sonnenaufgang/Ohne Wecker/Kurz vor Mittag/Nach dem ersten Kaffee",
      "Frühstück:Pancakes/Spiegelei/Croissants/Müsli",
      "Aktivität:Flohmarkt/Wandern/Baden/Museumsbesuch",
      "Abendessen:Lasagne/Curry/Suppe/Selbst belegte Pizza",
      "Abend:Brettspiel/Film/Badewanne/Spaziergang",
    ],
  ),
  topic(
    "future",
    "Our Life in 10 Years",
    "Romance",
    "Blicke in euren gemeinsamen Alltag von morgen.",
    "🔭",
    [
      "Wohnort:Am Meer/Am Stadtrand/In den Bergen/Mitten in der Stadt",
      "Beruf:Eigenes Atelier/Kleines Café/Forschung/Handwerksbetrieb",
      "Haustier:Hund/Katze/Kaninchen/Kein Haustier",
      "Alltag:Viel reisen/Großer Garten/Buntes Stadtleben/Ruhiges Landleben",
      "Ziel:Weltreise/Buch schreiben/Haus renovieren/Eine Sprache lernen",
    ],
  ),
  topic(
    "island",
    "Survival Island",
    "Funny",
    "Stell dein Team für eine einsame Insel zusammen.",
    "🏝️",
    [
      "Unterkunft:Baumhaus/Strandhütte/Höhle/Zelt",
      "Werkzeug:Messer/Seil/Feuerstein/Axt",
      "Nahrung:Kokosnüsse/Fisch/Beeren/Muscheln",
      "Begleiter:Papagei/Hund/Schildkröte/Affe",
      "Transport:Floß/Kanu/Segelboot/Schwimmen",
    ],
  ),
  topic(
    "hero",
    "Build a Superhero",
    "Funny",
    "Gib deiner Heldengeschichte eine überraschende Wendung.",
    "🦸",
    [
      "Superkraft:Fliegen/Teleportation/Zeit anhalten/Unsichtbarkeit",
      "Outfit:Umhang/Kapuzenpulli/Raumanzug/Rüstung",
      "Ausrüstung:Greifhaken/Schutzschild/Jetpack/Zauberstab",
      "Schwäche:Schluckauf/Katzenhaare/Discolicht/Höhenangst",
      "Begleiter:Roboter/Fledermaus/Unsichtbarer Fuchs/Drache",
    ],
  ),
  topic(
    "roadtrip",
    "Perfect Roadtrip",
    "Lifestyle",
    "Plane die Fahrt, für die der Weg das Ziel ist.",
    "🚐",
    [
      "Auto:Campingbus/Cabrio/Oldtimer/Elektroauto",
      "Route:Küstenstraße/Alpenpass/Wüstenpiste/Seenroute",
      "Musik:Indie/Disco/Rock/Podcasts",
      "Snacks:Obst/Chips/Butterbrote/Nüsse",
      "Stopp:Badesee/Aussichtsturm/Dorfmarkt/Nationalpark",
    ],
  ),
  topic(
    "restaurant",
    "Dream Restaurant",
    "Creative",
    "Eröffne dein eigenes Lokal für einen Abend.",
    "🍽️",
    [
      "Stil:Bistro/Trattoria/Ramenbar/Dachrestaurant",
      "Einrichtung:Marmor/Holz/Retro/Industrial",
      "Küche:Mediterran/Fusion/Regional/Asiatisch",
      "Hauptgericht:Risotto/Nudelsuppe/Ofengemüse/Pizza",
      "Dessert:Tiramisu/Sorbet/Apfelstrudel/Schokoladenmousse",
    ],
  ),
  topic(
    "park",
    "Build a Theme Park",
    "Funny",
    "Gestalte einen Park voller Überraschungen.",
    "🎡",
    [
      "Thema:Weltraum/Piraten/Märchen/Dinosaurier",
      "Achterbahn:Holzbahn/Looping/Wasserbahn/Minenbahn",
      "Attraktion:Riesenrad/Geisterbahn/Karussell/Klettergarten",
      "Essen:Zuckerwatte/Churros/Popcorn/Waffeln",
      "Show:Akrobatik/Lasershow/Feuertanz/Wassershow",
    ],
  ),
  topic(
    "gaming",
    "Dream Gaming Room",
    "Creative",
    "Entwirf deinen Lieblingsplatz für lange Spieleabende.",
    "🎮",
    [
      "Setup:Konsole/PC/Arcade/Handheld",
      "Monitor:Ultrawide/Doppelmonitor/Beamer/Fernseher",
      "Möbel:Sofa/Schreibtisch/Sitzsäcke/Stehpult",
      "Licht:Neon/Indirektes Licht/Sternenhimmel/Tageslicht",
      "Extra:Snackautomat/Retroregal/Lautsprecher/Getränkekühlschrank",
    ],
  ),
  topic(
    "million",
    "Millionaire for a Day",
    "Funny",
    "Gönn dir einen einzigen maßlosen Tag.",
    "💎",
    [
      "Haus:Penthouse/Schloss/Strandvilla/Berghütte",
      "Auto:Sportwagen/Limousine/Oldtimer/Elektroauto",
      "Reise:Privatinsel/Metropole/Safari/Weltumrundung",
      "Luxus:Flügel/Designeranzug/Juwel/Kunstwerk",
      "Erlebnis:Ballonfahrt/Privatkonzert/Sternedinner/Tauchgang",
    ],
  ),
];
export function getTopic(id: string) {
  const item = topics.find((t) => t.id === id);
  if (!item) throw new Error("Unbekanntes Thema");
  return item;
}
