import test from "node:test";
import assert from "node:assert/strict";
import { database, users } from "./database.ts";
import { initialSnake } from "../src/games/snake/engine.ts";
test("Snake host lease fences competing tabs and restores checkpoints after expiry", async () => {
  const { db, as, open, ready } = await database();
  try {
    const id = await open("snake-squared");
    await ready(id);
    const clients = [
      "30000000-0000-4000-8000-000000000001",
      "30000000-0000-4000-8000-000000000002",
    ];
    const control = async (
      client: number,
      epoch: number,
      action: string,
      snapshot: unknown = null,
    ) =>
      (
        await db.query<{
          result: {
            session: {
              host_id: string;
              host_epoch: number;
              status: string;
              checkpoint: unknown;
            };
          };
        }>("select public.snake_control($1,$2,$3,$4,$5) result", [
          id,
          clients[client],
          epoch,
          action,
          snapshot ? JSON.stringify(snapshot) : null,
        ])
      ).rows[0].result.session;
    assert.equal((await control(0, 0, "acquire")).host_epoch, 1);
    const state = initialSnake(users.slice(0, 2), 42);
    await control(0, 1, "checkpoint", state);
    await as(1);
    assert.equal((await control(1, 0, "acquire")).host_id, users[0]);
    await assert.rejects(control(1, 1, "checkpoint", state));
    await db.exec("reset role");
    await db.query(
      "update public.game_sessions set lease_until=now()-interval '1 second' where id=$1",
      [id],
    );
    await as(1);
    const resumed = await control(1, 1, "acquire");
    assert.equal(resumed.host_epoch, 2);
    assert.equal(resumed.status, "paused");
    assert.deepEqual(resumed.checkpoint, state);
    await as(0);
    await assert.rejects(control(0, 1, "checkpoint", state));
    await as(1);
    await control(1, 2, "resume");
    await assert.rejects(control(1, 2, "checkpoint", { ...state, tick: -1 }));
    await as(2);
    await assert.rejects(control(0, 2, "acquire"));
  } finally {
    await db.close();
  }
});
