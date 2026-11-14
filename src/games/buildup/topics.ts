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
      "Baustil:Holzhaus/Loft/Stadtvilla",
      "Umgebung:See/Wald/Altstadt",
      "Garten:Obstwiese/Blumenhof/Dachgarten",
      "Pool:Naturteich/Infinitypool/Whirlpool",
      "Wohnzimmer:Kaminzimmer/Bibliothek/Heimkino",
    ],
  ),
  topic(
    "pizza",
    "Perfect Pizza",
    "Creative",
    "Belege ein Stück Italien ganz nach deinem Geschmack.",
    "🍕",
    [
      "Teig:Dünn und knusprig/Dicker Rand/Vollkorn",
      "Sauce:Tomate/Pesto/Bianca",
      "Käse:Mozzarella/Gorgonzola/Parmesan",
      "Belag:Pilze/Salami/Artischocken",
      "Extra:Basilikum/Chiliöl/Rucola",
    ],
  ),
  topic(
    "car",
    "Dream Car",
    "Lifestyle",
    "Bau das Auto für deine nächste Ausfahrt.",
    "🚘",
    [
      "Typ:Cabrio/Kombi/Coupé",
      "Lack:Kirschrot/Salbeigrün/Graphit",
      "Felgen:Speichen/Chrom/Mattschwarz",
      "Innenraum:Leder/Stoff/Velours",
      "Extra:Panoramadach/Soundsystem/Sitzheizung",
    ],
  ),
  topic(
    "festival",
    "Festival Fit",
    "Creative",
    "Stell deinen Look für die erste Reihe zusammen.",
    "🎸",
    [
      "Oberteil:Bandshirt/Glitzertop/Jeansjacke",
      "Hose:Shorts/Cargo/Schlaghose",
      "Schuhe:Stiefel/Sneaker/Sandalen",
      "Zubehör:Sonnenbrille/Bauchtasche/Blumenkranz",
      "Frisur:Zöpfe/Offene Wellen/Bunter Iro",
    ],
  ),
  topic(
    "wedding",
    "Dream Wedding",
    "Romance",
    "Entwirf einen Tag, der ganz euch gehört.",
    "💐",
    [
      "Ort:Weingut/Strand/Bergalm",
      "Kleidung:Klassisch/Boho/Bunt",
      "Essen:Festmenü/Grillbuffet/Foodtrucks",
      "Musik:Jazztrio/DJ/Akustikduo",
      "Dekoration:Wildblumen/Kerzen/Laternen",
    ],
  ),
  topic(
    "sunday",
    "Perfect Sunday",
    "Lifestyle",
    "Füll einen freien Sonntag mit Lieblingsmomenten.",
    "☕",
    [
      "Aufstehen:Bei Sonnenaufgang/Ohne Wecker/Kurz vor Mittag",
      "Frühstück:Pancakes/Spiegelei/Croissants",
      "Aktivität:Flohmarkt/Wandern/Baden",
      "Abendessen:Lasagne/Curry/Suppe",
      "Abend:Brettspiel/Film/Badewanne",
    ],
  ),
  topic(
    "future",
    "Our Life in 10 Years",
    "Romance",
    "Blicke in euren gemeinsamen Alltag von morgen.",
    "🔭",
    [
      "Wohnort:Am Meer/Am Stadtrand/In den Bergen",
      "Beruf:Eigenes Atelier/Kleines Café/Forschung",
      "Haustier:Hund/Katze/Kaninchen",
      "Alltag:Viel reisen/Großer Garten/Buntes Stadtleben",
      "Ziel:Weltreise/Buch schreiben/Haus renovieren",
    ],
  ),
  topic(
    "island",
    "Survival Island",
    "Funny",
    "Stell dein Team für eine einsame Insel zusammen.",
    "🏝️",
    [
      "Unterkunft:Baumhaus/Strandhütte/Höhle",
      "Werkzeug:Messer/Seil/Feuerstein",
      "Nahrung:Kokosnüsse/Fisch/Beeren",
      "Begleiter:Papagei/Hund/Schildkröte",
      "Transport:Floß/Kanu/Segelboot",
    ],
  ),
  topic(
    "hero",
    "Build a Superhero",
    "Funny",
    "Gib deiner Heldengeschichte eine überraschende Wendung.",
    "🦸",
    [
      "Superkraft:Fliegen/Teleportation/Zeit anhalten",
      "Outfit:Umhang/Kapuzenpulli/Raumanzug",
      "Ausrüstung:Greifhaken/Schutzschild/Jetpack",
      "Schwäche:Schluckauf/Katzenhaare/Discolicht",
      "Begleiter:Roboter/Fledermaus/Unsichtbarer Fuchs",
    ],
  ),
  topic(
    "roadtrip",
    "Perfect Roadtrip",
    "Lifestyle",
    "Plane die Fahrt, für die der Weg das Ziel ist.",
    "🚐",
    [
      "Auto:Campingbus/Cabrio/Oldtimer",
      "Route:Küstenstraße/Alpenpass/Wüstenpiste",
      "Musik:Indie/Disco/Rock",
      "Snacks:Obst/Chips/Butterbrote",
      "Stopp:Badesee/Aussichtsturm/Dorfmarkt",
    ],
  ),
  topic(
    "restaurant",
    "Dream Restaurant",
    "Creative",
    "Eröffne dein eigenes Lokal für einen Abend.",
    "🍽️",
    [
      "Stil:Bistro/Trattoria/Ramenbar",
      "Einrichtung:Marmor/Holz/Retro",
      "Küche:Mediterran/Fusion/Regional",
      "Hauptgericht:Risotto/Nudelsuppe/Ofengemüse",
      "Dessert:Tiramisu/Sorbet/Apfelstrudel",
    ],
  ),
  topic(
    "park",
    "Build a Theme Park",
    "Funny",
    "Gestalte einen Park voller Überraschungen.",
    "🎡",
    [
      "Thema:Weltraum/Piraten/Märchen",
      "Achterbahn:Holzbahn/Looping/Wasserbahn",
      "Attraktion:Riesenrad/Geisterbahn/Karussell",
      "Essen:Zuckerwatte/Churros/Popcorn",
      "Show:Akrobatik/Lasershow/Feuertanz",
    ],
  ),
  topic(
    "gaming",
    "Dream Gaming Room",
    "Creative",
    "Entwirf deinen Lieblingsplatz für lange Spieleabende.",
    "🎮",
    [
      "Setup:Konsole/PC/Arcade",
      "Monitor:Ultrawide/Doppelmonitor/Beamer",
      "Möbel:Sofa/Schreibtisch/Sitzsäcke",
      "Licht:Neon/Indirektes Licht/Sternenhimmel",
      "Extra:Snackautomat/Retroregal/Lautsprecher",
    ],
  ),
  topic(
    "million",
    "Millionaire for a Day",
    "Funny",
    "Gönn dir einen einzigen maßlosen Tag.",
    "💎",
    [
      "Haus:Penthouse/Schloss/Strandvilla",
      "Auto:Sportwagen/Limousine/Oldtimer",
      "Reise:Privatinsel/Metropole/Safari",
      "Luxus:Flügel/Designeranzug/Juwel",
      "Erlebnis:Ballonfahrt/Privatkonzert/Sternedinner",
    ],
  ),
];
export function getTopic(id: string) {
  const item = topics.find((t) => t.id === id);
  if (!item) throw new Error("Unbekanntes Thema");
  return item;
}
