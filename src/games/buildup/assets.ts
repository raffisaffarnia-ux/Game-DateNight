export const destinations = [
  {
    file: "island",
    alt: "Strand mit türkisfarbenem Wasser",
    source: "photo-1519046904884-53103b34b206",
  },
  {
    file: "city",
    alt: "Hochhäuser einer Großstadt",
    source: "photo-1480714378408-67cf0d13bc1b",
  },
  {
    file: "mountains",
    alt: "Berggipfel im Gebirge",
    source: "photo-1464822759023-fed622ff2c3b",
  },
  {
    file: "coast",
    alt: "Blick auf die Mittelmeerküste",
    source: "photo-1533105079780-92b9be482077",
  },
];
export const breakfast = [
  {
    file: "pancakes",
    alt: "Pancakes mit Schokoladensauce",
    author: "Yulia Khlebnikova",
    link: "https://unsplash.com/photos/t_XM5pTc6wc",
  },
  {
    file: "eggs",
    alt: "Spiegeleier mit Kr�utern",
    author: "Laura Lauch",
    link: "https://unsplash.com/photos/osPCHdpXKxk",
  },
  {
    file: "croissants",
    alt: "Frisch gebackene Croissants",
    author: "Paul Hanaoka",
    link: "https://unsplash.com/photos/93NV4sBJs_M",
  },
  {
    file: "muesli",
    alt: "M�sli mit Joghurt und Erdbeeren",
    author: "Cosmin Ursea",
    link: "https://unsplash.com/photos/4i756gs8rWE",
  },
];
export function localPhoto(topic: string, step: number, option: number) {
  if (topic === "sunday" && step === 1) {
    const asset = breakfast[option];
    return asset
      ? {
          src: "/games/buildup/breakfast/" + asset.file + ".jpg",
          alt: asset.alt,
        }
      : null;
  }
  const asset =
    topic === "vacation" && step === 0 ? destinations[option] : null;
  return asset
    ? { src: "/games/buildup/travel/" + asset.file + ".jpg", alt: asset.alt }
    : null;
}
