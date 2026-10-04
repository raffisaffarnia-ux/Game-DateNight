import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./database.ts";
import { dateInZone, streakFor } from "../src/games/daily-us/logic.ts";
test("pair calendar handles local midnight and daylight-saving transitions", () => {
  assert.equal(dateInZone(new Date("2026-09-30T22:30:00Z")), "2026-10-01");
  assert.equal(dateInZone(new Date("2026-03-29T01:30:00Z")), "2026-03-29");
  assert.equal(streakFor(["2026-09-28", "2026-09-29"], "2026-09-30"), 2);
  assert.equal(
    streakFor(["2026-09-27", "2026-09-29", "2026-09-30"], "2026-09-30"),
    2,
  );
  assert.equal(streakFor([], "2026-09-30"), 0);
});
test("daily question is stable for a pair; private answers, locking and persistence", async () => {
  const { db, as, room } = await database();
  try {
    const context = async () =>
      (
        await db.query<{
          c: { entry_id: string; pair_id: string; day: string; streak: number };
        }>("select public.daily_context($1) c", [room])
      ).rows[0].c;
    const first = await context();
    await db.query("select public.daily_submit($1,'A holiday')", [
      first.entry_id,
    ]);
    await as(1);
    const second = await context();
    assert.equal(first.entry_id, second.entry_id);
    assert.equal(
      (await db.query("select * from public.daily_answers")).rows.length,
      0,
    );
    await db.query("select public.daily_submit($1,'A picnic')", [
      first.entry_id,
    ]);
    assert.equal(
      (await db.query("select * from public.daily_answers")).rows.length,
      2,
    );
    assert.equal((await context()).streak, 1);
    await assert.rejects(
      db.query("select public.daily_submit($1,'Changed')", [first.entry_id]),
    );
    await as(2);
    assert.equal(
      (await db.query("select * from public.daily_answers")).rows.length,
      0,
    );
    await assert.rejects(db.query("select public.daily_context($1)", [room]));
    await db.exec("reset role");
    await db.query(
      "update public.rooms set expires_at=now()-interval '1 hour' where id=$1",
      [room],
    );
    await as(0);
    await db.query("select public.resume_room($1)", [room]);
    assert.equal((await context()).entry_id, first.entry_id);
  } finally {
    await db.close();
  }
});
