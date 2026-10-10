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
    description: "See how often you think alike.",
    category: "Relationship",
    art: "orbits",
    status: "available",
  },
  {
    id: "snake-squared",
    title: "Snake²",
    description: "Classic Snake. Two players. One board.",
    category: "Arcade",
    art: "snake",
    status: "available",
  },
  {
    id: "do-you-know-me",
    title: "Do You Know Me?",
    description: "How well can you predict each other?",
    category: "Relationship",
    art: "tiles",
    status: "available",
  },
  {
    id: "deep-talk",
    title: "Deep Talk",
    description: "Questions worth talking about.",
    category: "Relationship",
    art: "cards",
    status: "available",
  },
  {
    id: "draw-together",
    title: "Draw Together",
    description: "Create something together.",
    category: "Creative",
    art: "drawing",
    status: "available",
  },
  {
    id: "daily-us",
    title: "Daily Us",
    description: "One question. Every day.",
    category: "Daily",
    art: "daily",
    status: "available",
  },
  { id: "relationship-bomb", title: "Relationship Bomb", description: "Defuse eight tiny challenges with teamwork.", category: "Co-op", art: "bomb", status: "available" },
  { id: "moral-sync", title: "Moral Sync", description: "Explore the choices that shape how you see the world.", category: "Conversation", art: "moral", status: "available" },
  { id: "rank-and-draw", title: "Rank & Draw", description: "Rank your favourites, then draw one for your partner.", category: "Creative", art: "rank", status: "available" },
];
