import test from "node:test";
import assert from "node:assert/strict";
import { database, users } from "./database.ts";

type StoredState = {
  [key: string]: unknown;
  phase: string;
  turn_user_id: string;
  conversation_boxes: Record<string, string>;
  active_prompt: string | null;
  lines: boolean[];
  boxes: (string | null)[];
  scores: Record<string, number>;
  scores_by_player?: Record<string, number>;
  score?: number;
};
const clientA = "20000000-0000-4000-8000-000000000001";
const clientB = "20000000-0000-4000-8000-000000000002";

async function session(db: Awaited<ReturnType<typeof database>>["db"], id: string) {
  return (await db.query<{ state: StoredState; question_ids: string[]; revision: number; status: string; game_type: string; host_epoch: number; host_id: string | null; host_client: string | null; starts_at: string | null }>(
    "select state,question_ids,revision,status,game_type,host_epoch,host_id,host_client,starts_at from public.game_sessions where id=$1", [id],
  )).rows[0];
}

async function dotsAction(db: Awaited<ReturnType<typeof database>>["db"], id: string, revision: number, action: string, payload: Record<string, unknown> = {}) {
  return db.query("select public.dots_action($1,$2,$3,$4::jsonb)", [id, revision, action, JSON.stringify(payload)]);
}

async function arcadeControl(db: Awaited<ReturnType<typeof database>>["db"], id: string, client: string, epoch: number, action: string, payload: Record<string, unknown> = {}) {
  return db.query("select public.arcade_control($1,$2,$3,$4,$5::jsonb)", [id, client, epoch, action, JSON.stringify(payload)]);
}

test("Dots & Dates serializes two-player turns, extra moves, fresh cards, completion and replay", async () => {
  const { db, as, open, ready } = await database();
  try {
    const id = await open("dots-and-dates");
    let current = await session(db, id);
    assert.equal(current.question_ids.length, 4);
    assert.deepEqual(Object.values(current.state.conversation_boxes).sort(), [...current.question_ids].sort());
    await ready(id);
    current = await session(db, id);

    await as(0);
    await dotsAction(db, id, current.revision, "move", { edge: 0 });
    current = await session(db, id);
    assert.equal(current.state.turn_user_id, users[1]);
    await assert.rejects(dotsAction(db, id, current.revision, "move", { edge: 1 }), /partner/);

    await as(1);
    await dotsAction(db, id, current.revision, "move", { edge: 4 });
    current = await session(db, id);
    await assert.rejects((async () => { await as(0); await dotsAction(db, id, current.revision, "move", { edge: 4 }); })(), /already been drawn/);

    await as(0);
    current = await session(db, id);
    await dotsAction(db, id, current.revision, "move", { edge: 20 });
    current = await session(db, id);
    await as(1);
    await dotsAction(db, id, current.revision, "move", { edge: 21 });
    current = await session(db, id);
    assert.equal(current.state.phase, "prompt");
    assert.equal(current.state.boxes[0], users[1]);
    assert.equal(current.state.turn_user_id, users[1]);
    assert.equal(current.state.active_prompt, current.question_ids[0]);
    assert.equal((await db.query("select * from public.game_answers where session_id=$1", [id])).rows.length, 0);
    assert.equal((await db.query("select * from public.couple_game_inputs where session_id=$1", [id])).rows.length, 0);

    await dotsAction(db, id, current.revision, "dismiss_prompt", { prompt_id: current.state.active_prompt });
    for (let edge = 0; edge < 40; edge++) {
      current = await session(db, id);
      if (current.status === "finished") break;
      if (current.state.phase === "prompt") {
        await as(0);
        await dotsAction(db, id, current.revision, "dismiss_prompt", { prompt_id: current.state.active_prompt });
        current = await session(db, id);
      }
      if (current.state.lines[edge]) continue;
      const player = current.state.turn_user_id === users[0] ? 0 : 1;
      await as(player);
      await dotsAction(db, id, current.revision, "move", { edge });
    }
    current = await session(db, id);
    if (current.state.phase === "prompt") {
      await as(0);
      await dotsAction(db, id, current.revision, "dismiss_prompt", { prompt_id: current.state.active_prompt });
      current = await session(db, id);
    }
    assert.equal(current.status, "finished");
    assert.equal(current.state.boxes.filter(Boolean).length, 16);
    assert.equal(Object.values(current.state.scores).reduce((sum, score) => sum + score, 0), 16);

    await as(0);
    const replay = await db.query<{ id: string }>("select public.replay_game($1) id", [id]);
    const next = await session(db, replay.rows[0].id);
    assert.equal(next.status, "lobby");
    assert.equal(next.question_ids.some((question) => current.question_ids.includes(question)), false);
  } finally {
    await db.close();
  }
});

test("Flipper Duo starts once, fences the host, pauses and persists only the final result", async () => {
  const { db, as, open, ready, room } = await database();
  try {
    const id = await open("flipper-duo");
    await ready(id);
    await as(0);
    await arcadeControl(db, id, clientA, 0, "start");
    let current = await session(db, id);
    assert.equal(current.status, "starting");
    const startsAt = current.starts_at;

    await as(1);
    await arcadeControl(db, id, clientB, 0, "start");
    current = await session(db, id);
    assert.equal(current.starts_at, startsAt);
    assert.equal(current.state.phase, "countdown");

    await as(0);
    await arcadeControl(db, id, clientA, 0, "acquire");
    current = await session(db, id);
    assert.equal(current.host_id, users[0]);
    assert.equal(current.host_client, clientA);
    assert.equal(current.host_epoch, 1);

    await db.query("select set_config('realtime.topic',$1,false)", [`room:${room}:session:${id}:input:${users[0]}`]);
    await db.exec("insert into realtime.messages values ('broadcast')");
    await db.query("select set_config('realtime.topic',$1,false)", [`room:${room}:session:${id}:host:1:${clientA}`]);
    await db.exec("insert into realtime.messages values ('broadcast')");
    await db.query("select set_config('realtime.topic',$1,false)", [`room:${room}:session:${id}:input:${users[1]}`]);
    await assert.rejects(db.exec("insert into realtime.messages values ('broadcast')"), /row-level security/);
    await as(1);
    await db.query("select set_config('realtime.topic',$1,false)", [`room:${room}:session:${id}:host:1:${clientA}`]);
    assert.ok((await db.query("select * from realtime.messages")).rows.length >= 1);

    await as(1);
    await assert.rejects(arcadeControl(db, id, clientB, 1, "finish", {
      score: 0, scores_by_player: { [users[0]]: 0, [users[1]]: 0 },
    }), /lease expired/);

    await as(0);
    await arcadeControl(db, id, clientA, 1, "pause");
    current = await session(db, id);
    assert.equal(current.status, "paused");
    await arcadeControl(db, id, clientA, 1, "resume");
    current = await session(db, id);
    assert.equal(current.status, "starting");

    await db.exec("reset role");
    await db.query("update public.game_sessions set starts_at=now()-interval '1 second' where id=$1", [id]);
    await as(0);
    await arcadeControl(db, id, clientA, 1, "heartbeat");
    current = await session(db, id);
    assert.equal(current.status, "playing");

    const scores = { [users[0]]: 420, [users[1]]: 180 };
    await arcadeControl(db, id, clientA, 1, "finish", { score: 600, scores_by_player: scores });
    current = await session(db, id);
    assert.equal(current.status, "finished");
    assert.equal(current.state.score, 600);
    assert.deepEqual(current.state.scores_by_player, scores);
    const revision = current.revision;
    await arcadeControl(db, id, clientA, 1, "finish", { score: 600, scores_by_player: scores });
    assert.equal((await session(db, id)).revision, revision);
    await as(0);
    const rematch = await db.query<{ id: string }>("select public.replay_game($1) id", [id]);
    const next = await session(db, rematch.rows[0].id);
    assert.equal(next.game_type, "flipper-duo");
    assert.equal(next.status, "lobby");
    assert.equal(next.state.phase, "lobby");
    assert.equal(next.state.score, 0);
  } finally {
    await db.close();
  }
});
