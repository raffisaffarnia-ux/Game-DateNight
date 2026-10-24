export type CardId = number;
export type Position = 0 | 1 | 2 | 3;
export type HerbertPhase = "peek" | "turn" | "drawn" | "final_slaps" | "finished";
export type HerbertAction = "peek" | "ready" | "draw" | "discard" | "swap" | "slap" | "call" | "settle";
export type HerbertState = {
 phase: HerbertPhase; turn_user: string; caller: string | null;
 occupied: Record<string, boolean[]>; discard: CardId | null; deck_count: number;
 drawn_by: string | null; peeked: string[]; last_action: string;
 finish_after: string | null; values: number[];
 hands?: Record<string, (CardId | null)[]>; scores?: Record<string, number>;
 winners?: string[]; caller_correct?: boolean | null;
};
export const suits = ["♣", "♦", "♥", "♠"] as const;
export const suitNames = ["Kreuz", "Karo", "Herz", "Pik"] as const;
export function cardFace(card: CardId) {
 const rank = card % 13 + 1, suit = Math.floor(card / 13);
 return { rank, label: ({1:"A",11:"B",12:"D",13:"K"} as Record<number,string>)[rank] ?? String(rank),
  suit: suits[suit], red: suit === 1 || suit === 2,
  description: suitNames[suit] + " " + (({1:"Ass",11:"Bube",12:"Dame",13:"König"} as Record<number,string>)[rank] ?? rank) };
}
