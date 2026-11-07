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

test("Herbert pops the real discard stack, preserves cards and never expires a turn",async()=>{
 const {db,as,open}=await database();
 try{
  const id=await open("herbert");
  const read=async()=> (await db.query<{state:{turn_deadline?:string;discard:number;drawn:number;draw_source:string;turn_user:string;phase:string};revision:number}>("select state,revision from public.game_sessions where id=$1",[id])).rows[0];
  const act=async(action:string,payload:Record<string,unknown>={})=>db.query("select public.herbert_action($1,$2,$3,$4,$5)",[id,randomUUID(),(await read()).revision,action,JSON.stringify(payload)]);
  for(const i of [0,1]){await as(i);await act("peek");await act("ready");}
  await as(0);
  let s=await read();assert.equal(s.state.turn_deadline,null);
  const originalTop=s.state.discard;
  await act("draw");const drawn=(await db.query<{v:{drawn:number}}>("select public.herbert_view($1) v",[id])).rows[0].v.drawn;
  await act("discard");await as(1);await act("take_discard");
  s=await read();assert.equal(s.state.drawn,null);assert.equal((await db.query<{v:{drawn:number}}>("select public.herbert_view($1) v",[id])).rows[0].v.drawn,drawn);assert.equal(s.state.discard,originalTop);assert.equal(s.state.draw_source,"discard");
  await as(0);await assert.rejects(act("swap",{position:0}),/am Zug/);
  await as(1);await act("swap",{position:0});
  await db.exec("reset role");
  const secret=(await db.query<{deck:number[];discards:number[];hands:Record<string,(number|null)[]>;drawn:number|null}>("select * from private.herbert_games where session_id=$1",[id])).rows[0];
  const cards=[...secret.deck,...secret.discards,...Object.values(secret.hands).flat().filter(x=>x!==null)];
  assert.equal(cards.length,52);assert.equal(new Set(cards).size,52);
  assert.equal(secret.hands[users[1]][0],drawn);
  await db.query("update private.herbert_games set turn_deadline=clock_timestamp()-interval '1 second' where session_id=$1",[id]);
  await as(0);const beforeTimeout=await read();await act("timeout");
  s=await read();assert.equal(s.state.turn_user,users[0]);assert.equal(s.revision,beforeTimeout.revision);
  await act("call");await as(1);await act("draw");await act("discard");
  assert.equal((await read()).state.phase,"final_slaps");
  await db.exec("reset role");
  await assert.rejects(db.query("update private.herbert_games set deck=array_append(deck,deck[1]) where session_id=$1",[id]),/herbert_unique_deck/);
 }finally{await db.close();}
});

test("Herbert preserves all 52 distinct physical cards across 90 turns and reshuffles",async()=>{
 const {db,as,open}=await database();
 try{
  const id=await open("herbert");
  const state=async()=> (await db.query<{revision:number;state:{turn_user:string}}>("select revision,state from public.game_sessions where id=$1",[id])).rows[0];
  const act=async(name:string)=>db.query("select public.herbert_action($1,$2,$3,$4,'{}')",[id,randomUUID(),(await state()).revision,name]);
  for(const seat of [0,1]){await as(seat);await act("peek");await act("ready");}
  for(let turn=0;turn<90;turn++){
   await as((await state()).state.turn_user===users[0]?0:1);
   await act("draw");await act("discard");
   await db.exec("reset role");
   const row=(await db.query<{valid:boolean}>("select private.herbert_deck_is_complete(deck,discards,hands,drawn) valid from private.herbert_games where session_id=$1",[id])).rows[0];
   assert.equal(row.valid,true,`turn ${turn+1}`);
   await as(0);
  }
 }finally{await db.close();}
});

test("Bomb accepts different preferences and ends on the fifth objective mistake",async()=>{
 const {db,as,open,ready,action}=await database();
 try{
  const id=await open("relationship-bomb");
  await db.exec("reset role");
  await db.query("update public.game_sessions set question_ids=array['rb-sync-01','rb-comm-01','rb-comm-01','rb-comm-01','rb-comm-01','rb-comm-01','rb-comm-01','rb-final-01'] where id=$1",[id]);
  await as(0);await ready(id);
  const state=async()=> (await db.query<{status:string;state:{strikes:number}}>("select status,state from public.game_sessions where id=$1",[id])).rows[0];
  for(let round=0;round<=5;round++){
   for(const seat of [0,1]){await as(seat);await action(id,round,"lock",{answer:round===0?(seat===0?"Eine Reise planen":"Das Geld sparen"):"Rot"});}
   const s=await state();assert.equal(s.state.strikes,round);
   assert.equal(s.status,round===5?"finished":"playing");
   if(round<5)for(const seat of [0,1]){await as(seat);await action(id,round,"next");}
  }
 }finally{await db.close();}
});


test("a fresh Bomb round offers seven distinct module types despite unequal pool sizes",async()=>{
 const {db,open}=await database();
 try{
  const id=await open('relationship-bomb');
  const rows=(await db.query<{category:string}>("select c.category from public.game_sessions s cross join lateral unnest(s.question_ids) q(id) join public.game_content c on c.id=q.id where s.id=$1 and c.category<>'FINAL DEFUSE'",[id])).rows;
  assert.equal(rows.length,7);assert.equal(new Set(rows.map(x=>x.category)).size,7);
 }finally{await db.close();}
});
