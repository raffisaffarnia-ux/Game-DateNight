import test from "node:test";
import assert from "node:assert/strict";
import { database, users } from "./database.ts";

test("Moral Sync keeps choices private, inserts Change My Mind, then advances", async () => {
  const { db, as, open, action, ready } = await database();
  try {
    const id = await open("moral-sync");
    await action(id, 0, "configure", { count: 10, categories: ["Mixed"], deep_mode: true });
    await ready(id);
    await action(id, 0, "lock", { choice: "A" });
    await as(1);
    assert.equal((await db.query("select * from public.couple_game_inputs where kind='moral_answer'")).rows.length, 0);
    await action(id, 0, "lock", { choice: "B" });
    assert.equal((await db.query("select * from public.couple_game_inputs where kind='moral_answer' and revealed")).rows.length, 2);

    await as(0); await action(id, 0, "continue");
    await as(1); await action(id, 0, "continue");
    await as(0); await action(id, 1, "lock", { choice: "C" });
    await as(1); await action(id, 1, "lock", { choice: "D" });
    await as(0); await action(id, 1, "continue");
    await as(1); await action(id, 1, "continue");
    let session = (await db.query<{ state: { phase: string } }>("select state from public.game_sessions where id=$1", [id])).rows[0];
    assert.equal(session.state.phase, "change");
    assert.equal((await db.query("select * from public.couple_game_inputs where round=1 and kind='next'")).rows.length, 0);
    await as(0); await action(id, 1, "change_mind", { choice: "stay" });
    await as(1); await action(id, 1, "change_mind", { choice: "unsure" });
    await as(0); await action(id, 1, "continue");
    await as(1); await action(id, 1, "continue");
    session = (await db.query<{ state: { phase: string }; round: number }>("select state,round from public.game_sessions where id=$1", [id])).rows[0];
    assert.equal(session.state.phase, "dilemma");
    assert.equal(session.round, 2);
  } finally {
    await db.close();
  }
});

test("Relationship Bomb hides a locked answer until both players lock", async () => {
  const { db, as, open, action, ready } = await database();
  try {
    const id = await open("relationship-bomb");
    await ready(id);
    const prompt = (await db.query<{ id: string }>("select question_ids[1] id from public.game_sessions where id=$1", [id])).rows[0].id;
    const answer = prompt === "rb-comm-01" ? "Blue"
      : prompt === "rb-comm-02" ? "Star"
      : prompt === "rb-dont-01" ? "Venice"
      : prompt === "rb-dont-02" ? "A greenhouse"
      : prompt === "rb-final-01" ? "Good food"
      : prompt === "rb-final-02" ? "Laughter" : "A";
    const payload = prompt.startsWith("rb-know-") ? { own: "A", prediction: "A" }
      : prompt.startsWith("rb-order-") ? { rank: ["A", "B", "C", "D"] }
      : prompt.startsWith("rb-fast-") ? { choices: ["A", "B", "C", "D"] }
      : prompt.startsWith("rb-one-word-") ? { answer: "closer" }
      : { answer };
    await action(id, 0, "lock", payload);
    await as(1);
    assert.equal((await db.query("select * from public.couple_game_inputs where kind='bomb'")).rows.length, 0);
    await action(id, 0, "lock", payload);
    assert.equal((await db.query("select * from public.couple_game_inputs where kind='bomb' and revealed")).rows.length, 2);
    const session = (await db.query<{ state: { phase: string } }>("select state from public.game_sessions where id=$1", [id])).rows[0];
    assert.equal(session.state.phase, "resolved");
  } finally {
    await db.close();
  }
});

test("Rank & Draw reveals rankings together and protects the hidden target", async () => {
  const { db, as, open, action, ready } = await database();
  try {
    const id = await open("rank-and-draw");
    await ready(id);
    const ranking = ["A", "B", "C", "D", "E"];
    await action(id, 0, "lock", { rank: ranking });
    await as(1);
    assert.equal((await db.query("select * from public.couple_game_inputs where kind='ranking'")).rows.length, 1);
    await action(id, 0, "lock", { rank: ranking });
    let session = (await db.query<{ state: { phase: string } }>("select state from public.game_sessions where id=$1", [id])).rows[0];
    assert.equal(session.state.phase, "reveal");

    await as(0); await action(id, 0, "continue");
    await as(1); await action(id, 0, "continue");
    session = (await db.query<{ state: { phase: string; creator_id: string } }>("select state from public.game_sessions where id=$1", [id])).rows[0];
    assert.equal(session.state.phase, "create");
    const creatorIndex = session.state.creator_id === users[0] ? 0 : 1;
    const guesserIndex = creatorIndex === 0 ? 1 : 0;
    await as(guesserIndex);
    assert.equal((await db.query("select * from public.couple_game_inputs where kind='target'")).rows.length, 0);
    await as(creatorIndex);
    await action(id, 0, "draw_finish");
    session = (await db.query<{ state: { phase: string } }>("select state from public.game_sessions where id=$1", [id])).rows[0];
    assert.equal(session.state.phase, "guess");
    await as(guesserIndex);
    await action(id, 0, "guess", { item: "A" });
    session = (await db.query<{ state: { phase: string; last_guess: string } }>("select state from public.game_sessions where id=$1", [id])).rows[0];
    assert.equal(session.state.phase, "compare");
    assert.equal(session.state.last_guess, "A");
    assert.equal((await db.query("select * from public.couple_game_inputs where kind='target' and revealed")).rows.length, 1);
  } finally {
    await db.close();
  }
});

