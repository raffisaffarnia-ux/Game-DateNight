import test from "node:test";
import assert from "node:assert/strict";
import {
  applyDotsMove,
  canSelectDotEdge,
  conversationCards,
  createDotsState,
  dismissDotsPrompt,
  dotsProgress,
  dotsWinner,
  getConversationCard,
  edgesForBox,
} from "../src/games/dots-and-dates/engine.ts";

test("two players close a box, receive an extra turn and reveal an optional card", () => {
  let state = createDotsState(["alex", "sam"]);
  assert.deepEqual(state.conversation_boxes, { "0": "dd01", "3": "dd02", "12": "dd03", "15": "dd04" });
  assert.ok(Object.values(state.conversation_boxes).every((id) => conversationCards[id]));
  assert.deepEqual(dotsProgress(state), { completed: 0, total: 16, percent: 0 });
  assert.deepEqual(edgesForBox(0), [0, 4, 20, 21]);
  state = applyDotsMove(state, "alex", 0);
  state = applyDotsMove(state, "sam", 4);
  state = applyDotsMove(state, "alex", 20);
  assert.equal(state.turn_user_id, "sam");
  state = applyDotsMove(state, "sam", 21);
  assert.equal(state.scores.sam, 1);
  assert.deepEqual(dotsProgress(state), { completed: 1, total: 16, percent: 6 });
  assert.equal(state.turn_user_id, "sam");
  assert.equal(state.phase, "prompt");
  assert.equal(state.active_prompt, "dd01");
  assert.equal(getConversationCard(state.active_prompt), conversationCards.dd01);
  assert.equal(canSelectDotEdge(state, 22, "sam"), false);
  assert.equal(dismissDotsPrompt(state).phase, "board");
});

test("rejects a duplicate line and a move from the player without the turn", () => {
  let state = createDotsState(["alex", "sam"]);
  state = applyDotsMove(state, "alex", 0);
  assert.throws(() => applyDotsMove(state, "alex", 1), /nicht möglich/);
  assert.throws(() => applyDotsMove(state, "sam", 0), /nicht möglich/);
});

test("two-player match fills every box and resolves the winner after optional cards", () => {
  let state = createDotsState(["alex", "sam"]);
  for (let edge = 0; edge < 40 && state.phase !== "result"; edge++) {
    if (state.phase === "prompt") state = dismissDotsPrompt(state);
    if (state.phase !== "board" || state.lines[edge]) continue;
    state = applyDotsMove(state, state.turn_user_id, edge);
  }
  if (state.phase === "prompt") state = dismissDotsPrompt(state);
  assert.equal(state.phase, "result");
  assert.equal(state.boxes.filter(Boolean).length, 16);
  assert.deepEqual(dotsProgress(state), { completed: 16, total: 16, percent: 100 });
  assert.equal(state.lines.every(Boolean), true);
  assert.equal(Object.values(state.scores).reduce((sum, score) => sum + score, 0), 16);
  assert.ok(["alex", "sam", null].includes(dotsWinner(state)));
});
