import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./database.ts";
test("Drawing protects the word and accepts only the other player’s exact guess", async () => {
  const { db, as, open, action, ready } = await database();
  try {
    const id = await open("draw-together");
    await action(id, 0, "mode", { mode: "guess" });
    await ready(id);
    const word = (
      await db.query<{ word: string }>("select public.drawing_word($1) word", [
        id,
      ])
    ).rows[0].word;
    assert.ok(word);
    await assert.rejects(db.query("select * from public.drawing_secrets"));
    await assert.rejects(action(id, 0, "guess", { value: word }));
    await as(1);
    assert.equal(
      (
        await db.query<{ word: string | null }>(
          "select public.drawing_word($1) word",
          [id],
        )
      ).rows[0].word,
      null,
    );
    await action(id, 0, "guess", { value: " " + word.toUpperCase() + " " });
    assert.equal(
      (
        await db.query<{ status: string }>(
          "select status from public.game_sessions where id=$1",
          [id],
        )
      ).rows[0].status,
      "round_end",
    );
    await action(id, 0, "next");
    assert.ok(
      (
        await db.query<{ word: string }>(
          "select public.drawing_word($1) word",
          [id],
        )
      ).rows[0].word,
    );
    await as(0);
    assert.equal(
      (
        await db.query<{ word: string | null }>(
          "select public.drawing_word($1) word",
          [id],
        )
      ).rows[0].word,
      null,
    );
  } finally {
    await db.close();
  }
});
test("Drawing persists bounded strokes, own undo and consent-based clear", async () => {
  const { db, as, open, action, ready } = await database();
  try {
    const id = await open("draw-together");
    await ready(id);
    const stroke = {
      tool: "pen",
      color: "#123456",
      width: 0.01,
      points: [
        { x: 0.1, y: 0.2 },
        { x: 0.4, y: 0.8 },
      ],
    };
    const commit = (key: string, version = 0, body = stroke) =>
      db.query("select public.commit_stroke($1,0,$2,$3,$4)", [
        id,
        version,
        key,
        JSON.stringify(body),
      ]);
    await commit("20000000-0000-4000-8000-000000000001");
    await as(1);
    await db.query("select public.undo_stroke($1,0)", [id]);
    assert.equal(
      (await db.query("select * from public.drawing_strokes where not removed"))
        .rows.length,
      1,
    );
    await action(id, 0, "clear_request");
    await assert.rejects(action(id, 0, "clear_confirm"));
    await as(0);
    await action(id, 0, "clear_confirm");
    assert.equal(
      (await db.query("select * from public.drawing_strokes where not removed"))
        .rows.length,
      0,
    );
    await assert.rejects(commit("20000000-0000-4000-8000-000000000002"));
    await assert.rejects(
      commit("20000000-0000-4000-8000-000000000002", 1, {
        ...stroke,
        points: [{ x: 2, y: 0 }],
      }),
    );
    await commit("20000000-0000-4000-8000-000000000003", 1);
    await action(id, 0, "finish");
    await assert.rejects(commit("20000000-0000-4000-8000-000000000004", 1));
    const replacement = (
      await db.query<{ id: string }>("select public.replay_game($1) id", [id])
    ).rows[0].id;
    assert.notEqual(replacement, id);
    await as(2);
    assert.equal(
      (await db.query("select * from public.drawing_strokes")).rows.length,
      0,
    );
  } finally {
    await db.close();
  }
});
