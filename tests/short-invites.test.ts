import test from "node:test";
import assert from "node:assert/strict";
import { database, users } from "./database.ts";

test("four-character invitations retain legacy links and throttle incorrect guesses", async () => {
 const {db,as}=await database();
 try {
  await as(0);
  const room=(await db.query<{id:string}>("select public.create_room('Alex') id")).rows[0].id;
  const code=(await db.query<{code:string}>("select code from public.rooms where id=$1",[room])).rows[0].code;
  assert.match(code,/^[2-9A-HJ-NP-Z]{4}$/);
  await as(1);
  assert.equal((await db.query<{id:string}>("select public.join_room($1,'Sam') id",[code.toLowerCase()])).rows[0].id,room);
  await db.exec("reset role");
  await db.query("update public.rooms set code='ABCDEF12' where id=$1",[room]);
  await db.query("update private.invite_attempts set window_start=now()-interval '2 minutes' where user_id=$1",[users[1]]);
  await as(1);
  assert.equal((await db.query<{id:string}>("select public.join_room('ABCDEF12','Sam') id")).rows[0].id,room);
  for(let i=0;i<8;i++)assert.equal((await db.query<{id:null}>("select public.join_room('ZZZZ','Sam') id")).rows[0].id,null);
  assert.equal((await db.query<{id:null}>("select public.join_room('ABCDEF12','Sam') id")).rows[0].id,null);
  await assert.rejects(db.query("select * from private.invite_attempts"),/permission denied/);
 }finally{await db.close();}
});
