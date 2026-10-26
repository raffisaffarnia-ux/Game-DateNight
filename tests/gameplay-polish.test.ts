import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { database, users } from "./database.ts";

test("new invitations close only the creator's old rooms, without the five-room limit", async () => {
 const {db,as,room}=await database();
 try {
  await as(1);
  const other=(await db.query<{id:string}>("select public.create_room('Sam') id")).rows[0].id;
  await as(0);
  for(let i=0;i<7;i++)await db.query("select public.create_room('Alex')");
  await db.exec("reset role");
  const rows=(await db.query<{id:string}>("select r.id from public.rooms r join public.room_members m on m.room_id=r.id where m.user_id=$1 and m.seat=1 and r.expires_at>now()",[users[0]])).rows;
  assert.equal(rows.length,1);assert.notEqual(rows[0].id,room);
  assert.equal((await db.query<{active:boolean}>("select expires_at>now() active from public.rooms where id=$1",[other])).rows[0].active,true);
 }finally{await db.close();}
});

test("Herbert pops the real discard stack, preserves cards and enforces the 20-second deadline",async()=>{
 const {db,as,open}=await database();
 try{
  const id=await open("herbert");
  const read=async()=> (await db.query<{state:{turn_deadline?:string;discard:number;drawn:number;draw_source:string;turn_user:string;phase:string};revision:number}>("select state,revision from public.game_sessions where id=$1",[id])).rows[0];
  const act=async(action:string,payload:Record<string,unknown>={})=>db.query("select public.herbert_action($1,$2,$3,$4,$5)",[id,randomUUID(),(await read()).revision,action,JSON.stringify(payload)]);
  for(const i of [0,1]){await as(i);await act("peek");await act("ready");}
  await as(0);
  let s=await read();assert.ok(s.state.turn_deadline);
  const deadline=s.state.turn_deadline, originalTop=s.state.discard;
  await act("draw");const drawn=(await read()).state.drawn;
  await act("discard");await as(1);await act("take_discard");
  s=await read();assert.equal(s.state.drawn,drawn);assert.equal(s.state.discard,originalTop);assert.equal(s.state.draw_source,"discard");
  await as(0);await assert.rejects(act("swap",{position:0}),/am Zug/);
  await as(1);await act("swap",{position:0});
  await db.exec("reset role");
  const secret=(await db.query<{deck:number[];discards:number[];hands:Record<string,(number|null)[]>;drawn:number|null}>("select * from private.herbert_games where session_id=$1",[id])).rows[0];
  const cards=[...secret.deck,...secret.discards,...Object.values(secret.hands).flat().filter(x=>x!==null)];
  assert.equal(cards.length,52);assert.equal(new Set(cards).size,52);
  assert.equal(secret.hands[users[1]][0],drawn);
  await db.query("update private.herbert_games set turn_deadline=clock_timestamp()-interval '1 second' where session_id=$1",[id]);
  await as(1);await act("timeout");
  s=await read();assert.equal(s.state.turn_user,users[1]);assert.notEqual(s.state.turn_deadline,deadline);
  const rev=s.revision;await act("timeout");assert.equal((await read()).revision,rev);
  await act("call");await db.exec("reset role");
  await db.query("update private.herbert_games set turn_deadline=clock_timestamp()-interval '1 second' where session_id=$1",[id]);
  await as(1);await act("timeout");assert.equal((await read()).state.phase,"final_slaps");
 }finally{await db.close();}
});
