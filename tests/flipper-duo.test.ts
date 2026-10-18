import test from "node:test";
import assert from "node:assert/strict";
import { createFlipperState, serveFlipperBall, stepFlipper } from "../src/games/flipper-duo/engine.ts";

const players = ["alex", "sam"];

test("serve is one-shot and a bumper awards points to a player", () => {
  let state = createFlipperState(players);
  state = serveFlipperBall(state);
  assert.equal(state.ballActive, true);
  assert.equal(serveFlipperBall(state), state);
  state = { ...state, ball: { x: 150, y: 190, vx: 0, vy: 0 } };
  state = stepFlipper(state, { left: false, right: false }, players);
  assert.ok(state.score > 0);
  assert.equal(state.scores_by_player.alex, state.score);
  assert.equal(state.lastEvent, "bumper");
});

test("quick follow-up hits build a combo and both players contribute", () => {
  let state = createFlipperState(players);
  state = serveFlipperBall(state);
  state = { ...state, ball: { x: 150, y: 190, vx: 0, vy: 0 } };
  state = stepFlipper(state, { left: false, right: false }, players);
  const first = state.score;
  state = { ...state, lastFlipper: "right", ball: { x: 330, y: 190, vx: 0, vy: 0 } };
  state = stepFlipper(state, { left: false, right: false }, players);
  assert.equal(state.combo, 2);
  assert.ok(state.score > first);
  assert.ok(state.scores_by_player.sam > 0);
});

test("a round ends cleanly after the third lost ball", () => {
  let state = createFlipperState(players);
  for (let lost = 1; lost <= 3; lost++) {
    state = serveFlipperBall(state);
    state = { ...state, ball: { x: 240, y: 694, vx: 0, vy: 0 } };
    state = stepFlipper(state, { left: false, right: false }, players);
    assert.equal(state.ballsRemaining, 3 - lost);
  }
  assert.equal(state.status, "finished");
  assert.equal(state.ballActive, false);
  assert.equal(serveFlipperBall(state), state);
});
