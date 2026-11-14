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
export function localPhoto(topic: string, step: number, option: number) {
  const asset =
    topic === "vacation" && step === 0 ? destinations[option] : null;
  return asset
    ? { src: "/games/buildup/travel/" + asset.file + ".jpg", alt: asset.alt }
    : null;
}
