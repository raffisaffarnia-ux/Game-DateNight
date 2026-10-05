import test from "node:test";
import assert from "node:assert/strict";
import { database, users } from "./database.ts";
import { initialSnake } from "../src/games/snake/engine.ts";
test("wallets, purchases and equipment are private, atomic and idempotent", async () => {
  const { db, as, room } = await database();
  try {
    await db.query("select public.my_profile()");
    assert.equal(
      (
        await db.query<{ coins: number }>(
          "select coins from public.player_profiles",
        )
      ).rows[0].coins,
      50,
    );
    await db.query("select public.buy_cosmetic('fox')");
    await db.query("select public.buy_cosmetic('fox')");
    assert.equal(
      (
        await db.query<{ coins: number }>(
          "select coins from public.player_profiles",
        )
      ).rows[0].coins,
      10,
    );
    await assert.rejects(
      db.query("select public.buy_cosmetic('bear')"),
      /Not enough coins/,
    );
    await assert.rejects(
      db.query("select public.equip_cosmetic('bear')"),
      /Unlock/,
    );
    await db.query("select public.equip_cosmetic('fox')");
    await assert.rejects(
      db.query("update public.player_profiles set coins=9999"),
      /permission denied/,
    );
    await assert.rejects(
      db.query("select private.award_coin($1,'fake',999,'fake')", [users[0]]),
      /permission denied/,
    );
    await as(1);
    assert.equal(
      (await db.query("select * from public.player_profiles")).rows.length,
      0,
    );
    const result = (
      await db.query<{ p: { players: Array<Record<string, unknown>> } }>(
        "select public.room_profiles($1) p",
        [room],
      )
    ).rows[0].p;
    assert.equal(
      result.players.find((x) => x.user_id === users[0])!.avatar,
      "fox",
    );
    assert.equal(
      result.players.some((x) => "coins" in x),
      false,
    );
    await as(2);
    await assert.rejects(
      db.query("select public.room_profiles($1)", [room]),
      /Room unavailable/,
    );
  } finally {
    await db.close();
  }
});
test("Snake victory and shared daily answers grant the documented rewards once", async () => {
  const { db, as, room, open, ready } = await database();
  try {
    const id = await open("snake-squared");
    await ready(id);
    const client = "30000000-0000-4000-8000-000000000001";
    await db.query("select public.snake_control($1,$2,0,'acquire')", [
      id,
      client,
    ]);
    const state = initialSnake(users.slice(0, 2), 42);
    state.status = "finished";
    state.winner = users[0];
    state.tick = 30;
    state.snakes[users[1]].alive = false;
    await db.query("select public.snake_control($1,$2,1,'checkpoint',$3)", [
      id,
      client,
      JSON.stringify(state),
    ]);
    assert.equal(
      (
        await db.query<{ coins: number }>(
          "select coins from public.player_profiles",
        )
      ).rows[0].coins,
      80,
    );
    await assert.rejects(
      db.query("select public.snake_control($1,$2,1,'checkpoint',$3)", [
        id,
        client,
        JSON.stringify(state),
      ]),
    );
    const daily = (
      await db.query<{ c: { entry_id: string } }>(
        "select public.daily_context($1) c",
        [room],
      )
    ).rows[0].c;
    await db.query("select public.daily_submit($1,'A picnic')", [
      daily.entry_id,
    ]);
    await as(1);
    assert.equal(
      (
        await db.query<{ coins: number }>(
          "select coins from public.player_profiles",
        )
      ).rows[0].coins,
      60,
    );
    await db.query("select public.daily_submit($1,'A walk')", [daily.entry_id]);
    assert.equal(
      (
        await db.query<{ coins: number }>(
          "select coins from public.player_profiles",
        )
      ).rows[0].coins,
      70,
    );
    await as(0);
    assert.equal(
      (
        await db.query<{ coins: number }>(
          "select coins from public.player_profiles",
        )
      ).rows[0].coins,
      90,
    );
    assert.equal(
      (
        await db.query<{ p: { flames: number } }>(
          "select public.room_profiles($1) p",
          [room],
        )
      ).rows[0].p.flames,
      2,
    );
  } finally {
    await db.close();
  }
});
test("matching answers award both players once and completion adds one shared flame", async () => {
  const { db, as, room, open, ready, action } = await database();
  try {
    const id = await open("this-or-that");
    await ready(id);
    for (let round = 0; round < 10; round++) {
      await as(0);
      await action(id, round, "answer", { value: "A" });
      await as(1);
      await action(id, round, "answer", { value: "A" });
      await action(id, round, "next");
    }
    for (const index of [0, 1]) {
      await as(index);
      assert.equal(
        (
          await db.query<{ coins: number }>(
            "select coins from public.player_profiles",
          )
        ).rows[0].coins,
        110,
      );
      assert.equal(
        (await db.query("select * from public.player_rewards")).rows.length,
        11,
      );
      assert.equal(
        (
          await db.query<{ p: { flames: number } }>(
            "select public.room_profiles($1) p",
            [room],
          )
        ).rows[0].p.flames,
        1,
      );
    }
    await db.exec("reset role");
    await db.query(
      "update public.game_sessions set revision=revision+1 where id=$1",
      [id],
    );
    await as(0);
    assert.equal(
      (
        await db.query<{ coins: number }>(
          "select coins from public.player_profiles",
        )
      ).rows[0].coins,
      110,
    );
    await as(2);
    assert.equal(
      (await db.query("select * from public.pair_flames")).rows.length,
      0,
    );
  } finally {
    await db.close();
  }
});
