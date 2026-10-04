import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";

test("migration enforces membership, capacity, expiry and RPC-only writes", async () => {
  const db = new PGlite();
  try {
    // Minimal Supabase infrastructure; the actual migration is tested unchanged.
    await db.exec(`
      create role anon; create role authenticated;
      create schema auth; create schema realtime;
      create table auth.users (id uuid primary key);
      create function auth.uid() returns uuid language sql stable as
        $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
      create function realtime.topic() returns text language sql stable as
        $$ select current_setting('realtime.topic', true) $$;
      create table realtime.messages (extension text);
      alter table realtime.messages enable row level security;
      grant usage on schema public, auth, realtime to authenticated;
      grant select, insert on realtime.messages to authenticated;
      create publication supabase_realtime;
    `);
    await db.exec(
      await readFile(
        new URL("../supabase/migrations/001_foundation.sql", import.meta.url),
        "utf8",
      ),
    );
    const ids = [
      "10000000-0000-4000-8000-000000000001",
      "10000000-0000-4000-8000-000000000002",
      "10000000-0000-4000-8000-000000000003",
    ];
    for (const id of ids)
      await db.query("insert into auth.users values ($1)", [id]);
    const as = async (id: string) => {
      await db.exec("reset role");
      await db.query("select set_config('request.jwt.claim.sub', $1, false)", [
        id,
      ]);
      await db.exec("set role authenticated");
    };
    await as(ids[0]);
    const created = await db.query<{ id: string }>(
      "select public.create_room('Alex') as id",
    );
    const id = created.rows[0].id;
    const room = await db.query<{ code: string }>(
      "select code from public.rooms where id=$1",
      [id],
    );
    assert.match(room.rows[0].code, /^[A-F0-9]{8}$/);
    await assert.rejects(
      db.query("select public.select_game($1, 'game-one')", [id]),
      /Wait for/,
    );
    await as(ids[1]);
    await db.query("select public.join_room($1, 'Sam')", [room.rows[0].code]);
    await db.query("select public.join_room($1, 'Sam')", [room.rows[0].code]);
    assert.equal(
      (await db.query("select * from public.room_members")).rows.length,
      2,
    );
    await db.query("select public.select_game($1, 'game-one')", [id]);
    await assert.rejects(
      db.query("select public.select_game($1, 'unknown')", [id]),
      /Unknown game/,
    );
    await as(ids[0]);
    assert.equal(
      (
        await db.query<{ current_game: string }>(
          "select current_game from public.rooms",
        )
      ).rows[0].current_game,
      "game-one",
    );
    await db.query("select set_config('realtime.topic', $1, false)", [
      `room:${id}`,
    ]);
    await db.exec("insert into realtime.messages values ('presence')");
    await assert.rejects(
      db.exec("update public.rooms set current_game=null"),
      /permission denied/,
    );
    await as(ids[2]);
    assert.equal((await db.query("select * from public.rooms")).rows.length, 0);
    assert.equal(
      (await db.query("select * from public.room_members")).rows.length,
      0,
    );
    assert.equal(
      (await db.query("select * from realtime.messages")).rows.length,
      0,
    );
    await assert.rejects(
      db.exec("insert into realtime.messages values ('presence')"),
      /row-level security/,
    );
    await assert.rejects(
      db.query("select public.join_room($1, 'Third')", [room.rows[0].code]),
      /already has two/,
    );
    await assert.rejects(
      db.query("select public.select_game($1, 'game-one')", [id]),
      /unavailable/,
    );
    await db.exec("reset role");
    await db.query(
      "update public.rooms set expires_at=now()-interval '1 second' where id=$1",
      [id],
    );
    await as(ids[0]);
    assert.equal((await db.query("select * from public.rooms")).rows.length, 0);
    await assert.rejects(
      db.query("select public.join_room($1, 'Alex')", [room.rows[0].code]),
      /expired/,
    );
  } finally {
    await db.close();
  }
});

