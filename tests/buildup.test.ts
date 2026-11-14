import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./database.ts";
import { topics } from "../src/games/buildup/topics.ts";
import {
  score,
  percent,
  type BuildState,
} from "../src/games/buildup/engine.ts";

test("BuildUp validates topics and weights real decisions", () => {
  assert.equal(new Set(topics.map((t) => t.id)).size, 19);
  for (const topic of topics)
    for (const step of topic.steps) assert.ok(new Set(step.options).size >= 3);
  const result = score({
    topic: "ball",
    builds: [
      [0, 1, 2, 1, 0],
      [1, 1, 2, 1, 2],
    ],
    guesses: null,
  });
  assert.equal(percent(result.matches, result.total), 60);
});

test("two private builders lock, predict, reveal and advance only together", async () => {
  const { db, room, as } = await database();
  try {
    const read = async () =>
      (
        await db.query<{ s: BuildState }>(
          "select state s from public.game_states where room_id=$1 and game_id='buildup'",
          [room],
        )
      ).rows[0].s;
    const move = (action: string, payload: object) =>
      db.query("select public.buildup_move($1,$2,$3)", [
        room,
        action,
        JSON.stringify(payload),
      ]);
    await as(0);
    await move("start", {
      mode: "partner",
      rounds: 3,
      topics: ["ball", "room", "date"],
    });
    let state = await read();
    assert.equal(new Set(state.topics).size, 3);
    const picks = [0, 0, 0, 0, 0];
    for (let round = 0; round < 3; round++) {
      for (const phase of ["build", "guess"]) {
        const args = { session: state.session, phase, round, picks };
        await as(0);
        await assert.rejects(move("lock", { ...args, picks: [9, 9, 9, 9, 9] }));
        await move("save", args);
        await move("lock", args);
        await move("lock", args);
        await as(1);
        assert.deepEqual(
          (
            await db.query<{ mine: Record<string, unknown> }>(
              "select public.buildup_mine($1) mine",
              [room],
            )
          ).rows[0].mine[phase],
          undefined,
        );
        assert.equal((await read()).history.length, round);
        await assert.rejects(db.query("select * from private.buildup_entries"));
        await move("lock", args);
      }
      state = await read();
      assert.equal(state.phase, "reveal");
      assert.deepEqual(score(state.history[round]).hits, [5, 5]);
      const args = { session: state.session, phase: "reveal", round };
      await move("next", args);
      await move("next", args);
      assert.equal((await read()).phase, "reveal");
      await as(0);
      await move("next", args);
      state = await read();
    }
    assert.equal(state.phase, "end");
    await move("start", {
      session: state.session,
      mode: "same",
      rounds: 3,
      topics: ["ball"],
    });
    state = await read();
    for (const player of [0, 1]) {
      await as(player);
      await move("lock", {
        session: state.session,
        phase: "build",
        round: 0,
        picks,
      });
    }
    assert.equal((await read()).phase, "reveal");
  } finally {
    await db.close();
  }
});

test("BuildUp rejects outsiders, malformed photos and late events from an old round", async () => {
  const { db, room, as } = await database();
  const read = async () =>
    (
      await db.query<{ state: BuildState }>(
        "select state from public.game_states where room_id=$1 and game_id='buildup'",
        [room],
      )
    ).rows[0]?.state;
  const move = (action: string, payload: object = {}) =>
    db.query("select public.buildup_move($1,$2,$3)", [
      room,
      action,
      JSON.stringify(payload),
    ]);
  try {
    await as(0);
    const settings = { mode: "same", rounds: 3, topics: ["ball"] };
    await move("configure", settings);
    await as(1);
    assert.deepEqual((await read()).settings?.topics, ["ball"]);
    await assert.rejects(move("start", settings));
    await as(0);
    await assert.rejects(
      move("start", {
        ...settings,
        photos: {
          "vacation:0:0": {
            src: "https://untrusted.example/p.jpg",
            link: "https://untrusted.example",
            author: "X",
          },
        },
      }),
    );
    await move("start", settings);
    const state = await read();
    const args = {
      session: state.session,
      phase: "build",
      round: 0,
      picks: [0, 0, 0, 0, 0],
    };
    await move("save", { ...args, picks: [2, 1] });
    assert.deepEqual(
      (
        await db.query<{ mine: { build: number[] } }>(
          "select public.buildup_mine($1) mine",
          [room],
        )
      ).rows[0].mine.build,
      [2, 1],
    );
    await move("lock", args);
    await as(2);
    assert.equal(await read(), undefined);
    await assert.rejects(move("lock", args));
    await assert.rejects(move("leave"));
    await as(1);
    await move("lock", args);
    assert.equal((await read()).phase, "reveal");
    assert.ok((await read()).revealed_at);
    await move("lock", args);
    assert.equal((await read()).history.length, 1);
    await move("next", { session: state.session, phase: "reveal", round: 0 });
    await as(0);
    await move("next", { session: state.session, phase: "reveal", round: 0 });
    await move("lock", args);
    assert.deepEqual((await read()).done, []);
    await move("leave");
    assert.equal(await read(), undefined);
  } finally {
    await db.close();
  }
});

test("BuildUp weights total decisions and both prediction directions", () => {
  assert.deepEqual(
    score({
      topic: "test",
      builds: [
        [0, 0, 0],
        [1, 1, 1],
      ],
      guesses: [
        [1, 1, 0],
        [0, 0, 0],
      ],
    }),
    { hits: [2, 3], matches: 5, total: 6 },
  );
  assert.equal(percent(5 + 1, 6 + 2), 75);
});
