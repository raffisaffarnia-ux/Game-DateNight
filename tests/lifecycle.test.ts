import test from "node:test";
import assert from "node:assert/strict";
import { database, users } from "./database.ts";
test("full private game finishes, keeps history and deduplicates replay", async () => {
  const { db, as, open, ready, action } = await database();
  try {
    const id = await open("this-or-that");
    await ready(id);
    for (let round = 0; round < 10; round++) {
      await as(0);
      await action(id, round, "answer", { value: "A" });
      await as(1);
      await action(id, round, "answer", { value: round % 2 ? "B" : "A" });
      await action(id, round, "next");
    }
    const finished = (
      await db.query<{
        status: string;
        finished_at: string;
        state: { matches: number };
      }>("select * from public.game_sessions where id=$1", [id])
    ).rows[0];
    assert.equal(finished.status, "finished");
    assert.equal(finished.state.matches, 5);
    assert.ok(finished.finished_at);
    assert.equal(
      (
        await db.query(
          "select * from public.game_answers where session_id=$1",
          [id],
        )
      ).rows.length,
      20,
    );
    const replay = async () =>
      (await db.query<{ id: string }>("select public.replay_game($1) id", [id]))
        .rows[0].id;
    const next = await replay();
    await as(0);
    assert.equal(await replay(), next);
    assert.notEqual(next, id);
    const state = (
      await db.query<{ ready: string[]; status: string }>(
        "select * from public.game_sessions where id=$1",
        [next],
      )
    ).rows[0];
    assert.deepEqual(state.ready, []);
    assert.equal(state.status, "lobby");
  } finally {
    await db.close();
  }
});
test("Realtime identities cannot spoof partner inputs or host snapshots", async () => {
  const { db, as, room, open, ready } = await database();
  try {
    const id = await open("snake-squared");
    await ready(id);
    const client = "30000000-0000-4000-8000-000000000001";
    await db.query("select public.snake_control($1,$2,0,'acquire')", [
      id,
      client,
    ]);
    const send = async (topic: string) => {
      await db.query("select set_config('realtime.topic',$1,false)", [topic]);
      return db.query("insert into realtime.messages values('broadcast')");
    };
    await send(`room:${room}:session:${id}:input:${users[0]}`);
    await assert.rejects(send(`room:${room}:session:${id}:input:${users[1]}`));
    await send(`room:${room}:session:${id}:host:1:${client}`);
    await as(1);
    await assert.rejects(send(`room:${room}:session:${id}:host:1:${client}`));
    await as(2);
    await assert.rejects(send(`room:${room}:session:${id}:input:${users[2]}`));
  } finally {
    await db.close();
  }
});
