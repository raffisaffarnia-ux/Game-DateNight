import type { GameId } from "../games/shared/types";
export type GameDefinition = {
  id: GameId;
  title: string;
  description: string;
  category: string;
  art: "cards" | "orbits" | "tiles" | "snake" | "drawing" | "daily" | "bomb" | "moral" | "rank" | "flipper" | "dots" | "herbert";
  status: "available";
  recommended?: boolean;
  daily?: boolean;
};
export const games: GameDefinition[] = [
  { id: "herbert", title: "Herbert", description: "Zehn Runden. Merken, tauschen, wegklatschen – weniger ist mehr.", category: "Arcade", art: "herbert", status: "available", recommended: true },
  {
    id: "daily-us",
    title: "Daily Us",
    description: "Eine Frage. Jeden Tag.",
    category: "Täglich",
    art: "daily",
    status: "available", daily: true,
  },
  {
    id: "this-or-that",
    title: "This or That",
    description: "Entdeckt, wie oft ihr gleich denkt.",
    category: "Beziehung",
    art: "orbits",
    status: "available",
  },
  {
    id: "snake-squared",
    title: "Snake²",
    description: "Klassisches Snake für zwei auf einem Spielfeld.",
    category: "Arcade",
    art: "snake",
    status: "available",
  },
  {
    id: "do-you-know-me",
    title: "Do You Know Me?",
    description: "Wie gut könnt ihr einander einschätzen?",
    category: "Beziehung",
    art: "tiles",
    status: "available",
  },
  {
    id: "deep-talk",
    title: "Deep Talk",
    description: "Fragen, über die es sich zu reden lohnt.",
    category: "Beziehung",
    art: "cards",
    status: "available",
  },
  {
    id: "draw-together",
    title: "Draw Together",
    description: "Erschafft gemeinsam etwas.",
    category: "Kreativ",
    art: "drawing",
    status: "available",
  },

  { id: "relationship-bomb", title: "Relationship Bomb", description: "Meistert acht kleine Herausforderungen im Team.", category: "Koop", art: "bomb", status: "available" },
  { id: "moral-sync", title: "Moral Sync", description: "Entdeckt, was eure Sicht auf die Welt prägt.", category: "Gespräch", art: "moral", status: "available" },
  { id: "rank-and-draw", title: "Rank", description: "Ordnet fünf Dinge in eure persönliche Reihenfolge und vergleicht, was euch wichtig ist.", category: "Beziehung", art: "rank", status: "available" },
  { id: "flipper-duo", title: "Flipper Duo", description: "Haltet den Ball zu zweit im Spiel und jagt euren Highscore.", category: "Arcade", art: "flipper", status: "available" },
  { id: "dots-and-dates", title: "Dots & Dates", description: "Verbindet Punkte, schließt Felder und entdeckt kleine Date-Night-Fragen.", category: "Arcade", art: "dots", status: "available" },
];
