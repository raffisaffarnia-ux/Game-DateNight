import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./database.ts";
test("private choices reveal atomically, score once, reject stale rounds and survive reads", async () => {
  const { db, as, open, action, ready } = await database();
  try {
    const id = await open("this-or-that");
    await ready(id);
    await action(id, 0, "answer", { value: "A" });
    await as(1);
    assert.equal(
      (await db.query("select * from public.game_answers")).rows.length,
      0,
    );
    await action(id, 0, "answer", { value: "A" });
    assert.equal(
      (await db.query("select * from public.game_answers where revealed")).rows
        .length,
      2,
    );
    let session = (
      await db.query<{ state: { matches: number }; round: number }>(
        "select state,round from public.game_sessions where id=$1",
        [id],
      )
    ).rows[0];
    assert.equal(session.state.matches, 1);
    await assert.rejects(action(id, 0, "answer", { value: "B" }));
    await action(id, 0, "next");
    await assert.rejects(action(id, 0, "next"));
    session = (
      await db.query<{ state: { matches: number }; round: number }>(
        "select state,round from public.game_sessions where id=$1",
        [id],
      )
    ).rows[0];
    assert.equal(session.round, 1);
    assert.equal(session.state.matches, 1);
    await as(2);
    assert.equal(
      (await db.query("select * from public.game_answers")).rows.length,
      0,
    );
    await assert.rejects(action(id, 1, "answer", { value: "A" }));
  } finally {
    await db.close();
  }
});
