export type RoundResult = {
  topic: string;
  builds: [number[], number[]];
  guesses: [number[], number[]] | null;
};
export type BuildState = {
  revealed_at?: number;
  photos?: Record<string, { src: string; author: string; link: string }>;
  settings?: {
    mode: "same" | "partner";
    rounds: number;
    topics: string[];
    category?: string;
  };
  session: string;
  mode: "same" | "partner";
  topics: string[];
  round: number;
  phase: "setup" | "build" | "guess" | "reveal" | "end";
  done: number[];
  ready: number[];
  progress: Record<string, number>;
  history: RoundResult[];
};
export function compare(left: number[], right: number[]) {
  return left.reduce((sum, value, i) => sum + Number(value === right[i]), 0);
}
export function score(round: RoundResult) {
  const [a, b] = round.builds;
  const guesses = round.guesses;
  const hits = guesses
    ? [compare(guesses[0], b), compare(guesses[1], a)]
    : [compare(a, b)];
  return {
    hits,
    total: a.length * hits.length,
    matches: hits.reduce((sum, n) => sum + n, 0),
  };
}
export function percent(matches: number, total: number) {
  return total ? Math.round((100 * matches) / total) : 0;
}
