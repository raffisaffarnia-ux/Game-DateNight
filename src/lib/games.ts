import type { GameId } from "../games/shared/types";
export type GameDefinition = {
  id: GameId;
  title: string;
  description: string;
  category: string;
  art: "cards" | "orbits" | "tiles" | "snake" | "drawing" | "daily" | "bomb" | "moral" | "rank";
  status: "available";
};
export const games: GameDefinition[] = [
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
  {
    id: "daily-us",
    title: "Daily Us",
    description: "Eine Frage. Jeden Tag.",
    category: "Täglich",
    art: "daily",
    status: "available",
  },
  { id: "relationship-bomb", title: "Relationship Bomb", description: "Meistert acht kleine Herausforderungen im Team.", category: "Koop", art: "bomb", status: "available" },
  { id: "moral-sync", title: "Moral Sync", description: "Entdeckt, was eure Sicht auf die Welt prägt.", category: "Gespräch", art: "moral", status: "available" },
  { id: "rank-and-draw", title: "Rank", description: "Ordne deine Favoriten und zeichne etwas für deinen Lieblingsmenschen.", category: "Kreativ", art: "rank", status: "available" },
];
