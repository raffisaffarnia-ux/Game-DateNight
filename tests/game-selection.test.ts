import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./database.ts";

test("library selection: fresh after exit, idempotent while active, no deletion or fake result", async () => {
  const { db, as, room } = await database();
  const select = (game: string | null, wheel = false) => db.query("select public.select_game($1,$2,$3)", [room, game, wheel]);
  const active = async () => (await db.query<{ active_session_id: string }>("select active_session_id from public.rooms where id=$1", [room])).rows[0].active_session_id;
  for (const game of ["herbert", "dots-and-dates", "moral-sync", "daily-us"]) {
    await select(game);
    const first = await active();
    await as(1);
    await select(game);
    assert.equal(await active(), first);
    await select(null);
    assert.equal(await active(), null);
    await select(game, true);
    const next = await active();
    assert.notEqual(next, first);
    const old = (await db.query<{status:string}>("select status from public.game_sessions where id=$1", [first])).rows[0];
    assert.notEqual(old.status, "finished");
    const fresh = (await db.query<{state:{wheel_mode:boolean}}>("select state from public.game_sessions where id=$1", [next])).rows[0];
    assert.equal(fresh.state.wheel_mode, true);
    await as(0);
  }
  await as(2);
  await assert.rejects(select("herbert"), /Raum nicht verfügbar/);
  await db.close();
});

