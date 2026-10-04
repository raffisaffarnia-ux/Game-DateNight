import test from "node:test";
import assert from "node:assert/strict";
import {
  initialSnake,
  tick,
  queueTurn,
  validSnapshot,
} from "../src/games/snake/engine.ts";
import type { Direction } from "../src/games/snake/types.ts";
test("Snake is deterministic, grows and rejects reversals and double turns", () => {
  const a = initialSnake(["a", "b"], 123);
  assert.deepEqual(a, initialSnake(["a", "b"], 123));
  a.food = { x: 6, y: 7 };
  const b = tick(a);
  assert.equal(b.snakes.a.score, 1);
  assert.equal(b.snakes.a.body.length, 4);
  assert.equal(a.tick, 0);
  const q: Partial<Record<string, Direction>> = {};
  queueTurn(a, q, "a", "left");
  assert.deepEqual(q, {});
  queueTurn(a, q, "a", "up");
  queueTurn(a, q, "a", "left");
  assert.equal(q.a, "up");
  assert.ok(validSnapshot(b, ["a", "b"]));
  assert.equal(validSnapshot({ ...b, tick: -1 }, ["a", "b"]), false);
});
test("Snake resolves walls, own body, opposing body, head-on and head swap", () => {
  let s = initialSnake(["a", "b"], 1);
  s.snakes.a.body = [
    { x: 23, y: 7 },
    { x: 22, y: 7 },
  ];
  assert.equal(tick(s).winner, "b");
  s = initialSnake(["a", "b"], 1);
  s.snakes.a.body = [
    { x: 4, y: 4 },
    { x: 4, y: 5 },
    { x: 5, y: 5 },
    { x: 5, y: 4 },
    { x: 6, y: 4 },
  ];
  assert.equal(tick(s).snakes.a.alive, false);
  s = initialSnake(["a", "b"], 1);
  s.snakes.b.body = [
    { x: 6, y: 6 },
    { x: 6, y: 7 },
    { x: 6, y: 8 },
  ];
  assert.equal(tick(s).snakes.a.alive, false);
  s = initialSnake(["a", "b"], 1);
  s.snakes.b.body = [
    { x: 7, y: 7 },
    { x: 8, y: 7 },
  ];
  assert.equal(tick(s).winner, null);
  assert.equal(tick(s).status, "finished");
  s = initialSnake(["a", "b"], 1);
  s.snakes.b.body = [
    { x: 6, y: 7 },
    { x: 7, y: 7 },
  ];
  assert.equal(tick(s).winner, null);
  assert.equal(tick(s).snakes.a.alive, false);
});
test("Food never spawns inside either snake", () => {
  for (let seed = 1; seed < 200; seed++) {
    const s = initialSnake(["a", "b"], seed);
    assert.ok(
      !Object.values(s.snakes).some((a) =>
        a.body.some((p) => p.x === s.food.x && p.y === s.food.y),
      ),
    );
  }
});
