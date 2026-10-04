import test from "node:test";
import assert from "node:assert/strict";
import { database, users } from "./database.ts";

test("new sessions never reuse allocated questions, including another room with the same pair", async () => {
  const { db, as, room, open } = await database();
  try {
    const seen = new Set<string>();
    for (let i = 0; i < 15; i++) {
      const id = await open("this-or-that");
      const { question_ids } = (
        await db.query<{ question_ids: string[] }>(
          "select question_ids from public.game_sessions where id=$1",
          [id],
        )
      ).rows[0];
      assert.equal(question_ids.length, 10);
      for (const q of question_ids) {
        assert.ok(!seen.has(q));
        seen.add(q);
      }
    }
    const second = (
      await db.query<{ id: string }>("select public.create_room('Alex') id")
    ).rows[0].id;
    const code = (
      await db.query<{ code: string }>(
        "select code from public.rooms where id=$1",
        [second],
      )
    ).rows[0].code;
    await as(1);
    await db.query("select public.join_room($1,'Sam')", [code]);
    const next = (
      await db.query<{ id: string }>(
        "select public.open_game($1,'this-or-that',true) id",
        [second],
      )
    ).rows[0].id;
    const questions = (
      await db.query<{ question_ids: string[] }>(
        "select question_ids from public.game_sessions where id=$1",
        [next],
      )
    ).rows[0].question_ids;
    assert.ok(questions.every((q) => !seen.has(q)));
    await assert.rejects(db.query("select * from private.question_history"));
    await as(2);
    await assert.rejects(
      db.query("select public.open_game($1,'this-or-that',true)", [room]),
    );
  } finally {
    await db.close();
  }
});

test("conversation decks, drawing prompts and daily dates exclude previous questions", async () => {
  const { db, open, action, ready, room } = await database();
  try {
    const seen = new Set<string>();
    for (let i = 0; i < 3; i++) {
      const id = await open("deep-talk");
      await action(id, 0, "deck", { deck: "Us" });
      const q = (
        await db.query<{ question_ids: string[] }>(
          "select question_ids from public.game_sessions where id=$1",
          [id],
        )
      ).rows[0].question_ids;
      assert.equal(q.length, 10);
      q.forEach((id) => {
        assert.ok(!seen.has(id));
        seen.add(id);
      });
    }
    const words = new Set<string>();
    for (let i = 0; i < 3; i++) {
      const id = await open("draw-together");
      await action(id, 0, "mode", { mode: "guess" });
      await ready(id);
      const word = (
        await db.query<{ word: string }>(
          "select public.drawing_word($1) word",
          [id],
        )
      ).rows[0].word;
      assert.ok(word);
      assert.ok(!words.has(word));
      words.add(word);
    }
    const first = (
      await db.query<{ c: { entry_id: string } }>(
        "select public.daily_context($1) c",
        [room],
      )
    ).rows[0].c;
    await db.exec("reset role");
    const q = (
      await db.query<{ question_id: string }>(
        "update public.daily_entries set day=day-1 where id=$1 returning question_id",
        [first.entry_id],
      )
    ).rows[0].question_id;
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [
      users[0],
    ]);
    await db.exec("set role authenticated");
    const second = (
      await db.query<{ c: { entry_id: string } }>(
        "select public.daily_context($1) c",
        [room],
      )
    ).rows[0].c;
    assert.notEqual(second.entry_id, first.entry_id);
    assert.notEqual(
      (
        await db.query<{ question_id: string }>(
          "select question_id from public.daily_entries where id=$1",
          [second.entry_id],
        )
      ).rows[0].question_id,
      q,
    );
  } finally {
    await db.close();
  }
});

test("Snake mode is shared, locks when ready, and rejects a different checkpoint mode", async () => {
  const { db, open, action, ready } = await database();
  try {
    const id = await open("snake-squared");
    await action(id, 0, "mode", { mode: "together" });
    assert.equal(
      (
        await db.query<{ state: { snake_mode: string } }>(
          "select state from public.game_sessions where id=$1",
          [id],
        )
      ).rows[0].state.snake_mode,
      "together",
    );
    await assert.rejects(action(id, 0, "mode", { mode: "invalid" }));
    await ready(id);
    await assert.rejects(action(id, 0, "mode", { mode: "versus" }));
    const client = "30000000-0000-4000-8000-000000000001";
    await db.query("select public.snake_control($1,$2,0,'acquire')", [
      id,
      client,
    ]);
    await assert.rejects(
      db.query("select public.snake_control($1,$2,1,'checkpoint',$3)", [
        id,
        client,
        JSON.stringify({ mode: "versus" }),
      ]),
    );
  } finally {
    await db.close();
  }
});
