export type Direction = "up" | "down" | "left" | "right";
export type Position = { x: number; y: number };
export type SnakeMode = "versus" | "together";
export type SnakeState = {
  mode?: SnakeMode;
  snakes: Record<
    string,
    { body: Position[]; direction: Direction; alive: boolean; score: number }
  >;
  food: Position;
  tick: number;
  seed: number;
  status: "playing" | "finished";
  winner: string | null;
};
