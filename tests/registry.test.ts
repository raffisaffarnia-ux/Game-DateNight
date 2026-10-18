import test from "node:test";
import assert from "node:assert/strict";
import { games } from "../src/lib/games.ts";
test("registry has eleven unique available games", () => {
  assert.equal(games.length, 11);
  assert.equal(new Set(games.map((g) => g.id)).size, 11);
  assert.equal(games.find((game) => game.id === "flipper-duo")?.category, "Arcade");
  assert.equal(games.find((game) => game.id === "dots-and-dates")?.category, "Arcade");
  for (const g of games) {
    assert.match(g.id, /^[a-z0-9-]+$/);
    assert.equal(g.status, "available");
    assert.ok(g.title && g.description && g.category);
  }
});

