import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./database.ts";
test("Deep Talk locks a shuffled deck, alternates next and saves privately", async () => {
  const { db, as, open, action, ready } = await database();
  try {
    const id = await open("deep-talk");
    await action(id, 0, "deck", { deck: "Us" });
    await ready(id);
    const s = (
      await db.query<{ question_ids: string[] }>(
        "select question_ids from public.game_sessions where id=$1",
        [id],
      )
    ).rows[0];
    assert.equal(new Set(s.question_ids).size, 10);
    await action(id, 0, "save");
    await as(1);
    assert.equal(
      (await db.query("select * from public.saved_questions")).rows.length,
      0,
    );
    await assert.rejects(action(id, 0, "next"));
    await as(0);
    await action(id, 0, "next");
    await assert.rejects(action(id, 1, "next"));
    await as(1);
    await action(id, 1, "next");
  } finally {
    await db.close();
  }
});
test("Know Me hides submissions and only the alternating subject awards points", async () => {
  const { db, as, open, action, ready } = await database();
  try {
    const id = await open("do-you-know-me");
    await ready(id);
    await action(id, 0, "answer", { value: "Pasta" });
    await as(1);
    assert.equal(
      (await db.query("select * from public.game_answers")).rows.length,
      0,
    );
    await action(id, 0, "answer", { value: "Noodles" });
    await assert.rejects(action(id, 0, "judge", { accepted: true }));
    await as(0);
    await action(id, 0, "judge", { accepted: true });
    await assert.rejects(action(id, 0, "judge", { accepted: true }));
    await action(id, 0, "next");
    await action(id, 1, "answer", { value: "Beach" });
    await as(1);
    await action(id, 1, "answer", { value: "Mountains" });
    await action(id, 1, "judge", { accepted: false });
    const s = (
      await db.query<{ state: { scores: Record<string, number> } }>(
        "select state from public.game_sessions where id=$1",
        [id],
      )
    ).rows[0];
    assert.equal(
      Object.values(s.state.scores).reduce((a, b) => a + b, 0),
      1,
    );
  } finally {
    await db.close();
  }
});
