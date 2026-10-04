import { PGlite } from "@electric-sql/pglite";
import { readdir, readFile } from "node:fs/promises";
export const users = [
  "10000000-0000-4000-8000-000000000001",
  "10000000-0000-4000-8000-000000000002",
  "10000000-0000-4000-8000-000000000003",
];
export async function database() {
  const db = new PGlite();
  await db.exec(`create role anon;create role authenticated;create schema auth;create schema realtime;
 create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 create function realtime.topic() returns text language sql stable as $$ select current_setting('realtime.topic',true) $$;
 create table realtime.messages(extension text);alter table realtime.messages enable row level security;
 grant usage on schema public,auth,realtime to authenticated;grant select,insert on realtime.messages to authenticated;create publication supabase_realtime;`);
  const folder = new URL("../supabase/migrations/", import.meta.url);
  for (const file of (await readdir(folder))
    .filter((f) => f.endsWith(".sql"))
    .sort())
    await db.exec(await readFile(new URL(file, folder), "utf8"));
  for (const id of users)
    await db.query("insert into auth.users values($1)", [id]);
  async function as(index: number) {
    await db.exec("reset role");
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [
      users[index],
    ]);
    await db.exec("set role authenticated");
  }
  await as(0);
  const room = (
    await db.query<{ id: string }>("select public.create_room('Alex') id")
  ).rows[0].id;
  const code = (
    await db.query<{ code: string }>(
      "select code from public.rooms where id=$1",
      [room],
    )
  ).rows[0].code;
  await as(1);
  await db.query("select public.join_room($1,'Sam')", [code]);
  await as(0);
  async function open(game: string) {
    return (
      await db.query<{ id: string }>("select public.open_game($1,$2,true) id", [
        room,
        game,
      ])
    ).rows[0].id;
  }
  async function action(
    id: string,
    round: number,
    action: string,
    payload: Record<string, unknown> = {},
  ) {
    return db.query("select public.game_action($1,$2,$3,$4)", [
      id,
      round,
      action,
      JSON.stringify(payload),
    ]);
  }
  async function ready(id: string) {
    await as(0);
    await action(id, 0, "ready");
    await as(1);
    await action(id, 0, "ready");
    await as(0);
  }
  return { db, as, room, code, open, action, ready };
}
