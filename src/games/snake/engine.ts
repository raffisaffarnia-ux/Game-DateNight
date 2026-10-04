import type { Direction, Position, SnakeState, SnakeMode } from "./types";
export const GRID = 24;
export const TICK_MS = 100;
export const TEAM_GOAL = 20;
const vectors: Record<Direction, Position> = {
  up: { x: 0, y: -1 },
  down: { x: 0, y: 1 },
  left: { x: -1, y: 0 },
  right: { x: 1, y: 0 },
};
const opposite: Record<Direction, Direction> = {
  up: "down",
  down: "up",
  left: "right",
  right: "left",
};
export const isDirection = (value: unknown): value is Direction =>
  typeof value === "string" && Object.hasOwn(vectors, value);
const same = (a: Position, b: Position) => a.x === b.x && a.y === b.y;
function food(state: SnakeState) {
  let seed = state.seed | 0;
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  state.seed = seed >>> 0;
  const free: Position[] = [];
  for (let y = 0; y < GRID; y++)
    for (let x = 0; x < GRID; x++)
      if (
        !Object.values(state.snakes).some((s) =>
          s.body.some((p) => p.x === x && p.y === y),
        )
      )
        free.push({ x, y });
  if (free.length) state.food = free[state.seed % free.length];
  else {
    state.status = "finished";
    state.winner = null;
  }
}
export function initialSnake(
  ids: string[],
  seed: number,
  mode: SnakeMode = "versus",
): SnakeState {
  const state: SnakeState = {
    mode,
    snakes: {
      [ids[0]]: {
        body: [
          { x: 5, y: 7 },
          { x: 4, y: 7 },
          { x: 3, y: 7 },
        ],
        direction: "right",
        alive: true,
        score: 0,
      },
      [ids[1]]: {
        body: [
          { x: 18, y: 16 },
          { x: 19, y: 16 },
          { x: 20, y: 16 },
        ],
        direction: "left",
        alive: true,
        score: 0,
      },
    },
    food: { x: 0, y: 0 },
    tick: 0,
    seed: seed || 1,
    status: "playing",
    winner: null,
  };
  food(state);
  return state;
}
/** A single accepted turn per tick prevents two rapid inputs from reversing a snake. */
export function queueTurn(
  state: SnakeState,
  queue: Partial<Record<string, Direction>>,
  id: string,
  direction: Direction,
) {
  const snake = state.snakes[id];
  if (
    snake &&
    snake.alive &&
    !queue[id] &&
    direction !== opposite[snake.direction] &&
    direction !== snake.direction
  )
    queue[id] = direction;
}
export function tick(
  state: SnakeState,
  inputs: Partial<Record<string, Direction>> = {},
): SnakeState {
  if (state.status === "finished") return state;
  const next = structuredClone(state);
  next.tick++;
  const ids = Object.keys(next.snakes),
    heads: Record<string, Position> = {},
    growing: Record<string, boolean> = {};
  for (const id of ids) {
    const s = next.snakes[id];
    const d = inputs[id];
    if (d && d !== opposite[s.direction]) s.direction = d;
    const v = vectors[s.direction];
    heads[id] = {
      x: (s.body[0].x + v.x + GRID) % GRID,
      y: (s.body[0].y + v.y + GRID) % GRID,
    };
    growing[id] = same(heads[id], state.food);
  }
  if (next.mode === "together" && ids.every((id) => growing[id]))
    growing[ids[1]] = false;
  for (const id of ids) {
    const head = heads[id];
    let dead = false;
    for (const other of ids) {
      // Team mates can pass through each other; each snake still avoids its own body.
      if (next.mode === "together" && other !== id) continue;
      const body = state.snakes[other].body;
      const occupied = growing[other] ? body : body.slice(0, -1);
      if (occupied.some((p) => same(head, p))) dead = true;
      if (
        other !== id &&
        (same(head, heads[other]) ||
          (same(head, body[0]) && same(heads[other], state.snakes[id].body[0])))
      )
        dead = true;
    }
    next.snakes[id].alive = !dead;
  }
  let ate = false;
  for (const id of ids) {
    const s = next.snakes[id];
    if (!s.alive) continue;
    s.body.unshift(heads[id]);
    if (growing[id]) {
      s.score++;
      ate = true;
    } else s.body.pop();
  }
  const living = ids.filter((id) => next.snakes[id].alive);
  if (living.length < 2) {
    next.status = "finished";
    next.winner = next.mode === "together" ? null : (living[0] ?? null);
  } else if (
    next.mode === "together" &&
    Object.values(next.snakes).reduce((sum, s) => sum + s.score, 0) >= TEAM_GOAL
  ) {
    next.status = "finished";
    next.winner = null;
  } else if (ate) food(next);
  return next;
}
export function validSnapshot(
  value: unknown,
  ids: string[],
): value is SnakeState {
  if (!value || typeof value !== "object") return false;
  const s = value as SnakeState;
  const point = (p: Position) =>
    p &&
    Number.isInteger(p.x) &&
    Number.isInteger(p.y) &&
    p.x >= 0 &&
    p.x < GRID &&
    p.y >= 0 &&
    p.y < GRID;
  return (
    Number.isSafeInteger(s.tick) &&
    s.tick >= 0 &&
    Number.isInteger(s.seed) &&
    s.seed >= 0 &&
    s.seed <= 4294967295 &&
    ["playing", "finished"].includes(s.status) &&
    (s.mode === undefined || ["versus", "together"].includes(s.mode)) &&
    point(s.food) &&
    !!s.snakes &&
    Object.keys(s.snakes).length === 2 &&
    ids.every((id) => {
      const a = s.snakes[id];
      return (
        a &&
        Array.isArray(a.body) &&
        a.body.length >= 1 &&
        a.body.length <= GRID * GRID &&
        a.body.every(point) &&
        isDirection(a.direction) &&
        typeof a.alive === "boolean" &&
        Number.isSafeInteger(a.score) &&
        a.score >= 0
      );
    }) &&
    (s.winner === null || ids.includes(s.winner))
  );
}
