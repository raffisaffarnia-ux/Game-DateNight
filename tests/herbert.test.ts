import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import type { HerbertState } from "../src/games/herbert/types.ts";
import { database, users } from "./database.ts";

test("Herbert: authoritative two-player lifecycle, privacy and edge cases", async t => {
 const {db,as,open,action:generic,room}=await database();
 let sid=await open("herbert");
 const session=async()=> (await db.query<{state:HerbertState & {deck?:unknown;drawn?:unknown};revision:number;status:string;ready:string[]}>("select state,revision,status,ready from public.game_sessions where id=$1",[sid])).rows[0];
 const act=async(action:string,payload:Record<string,unknown>={},id=randomUUID(),revision?:number)=>{
  const rev=revision??(await session()).revision;
  return (await db.query<{result:{ok?:boolean;peek?:number[];drawn?:number|null}}>("select public.herbert_action($1,$2,$3,$4,$5) result",[sid,id,rev,action,JSON.stringify(payload)])).rows[0].result;
 };
 const view=async()=> (await db.query<{result:{ok?:boolean;peek?:number[];drawn?:number|null}}>("select public.herbert_view($1) result",[sid])).rows[0].result;
 const secret=async()=>{
  await db.exec("reset role");
  const h=(await db.query<{hands:Record<string,(number|null)[]>;deck:number[];discards:number[];drawn:number|null;turn_user:string;phase:string}>("select * from private.herbert_games where session_id=$1",[sid])).rows[0];
  await as(0);return h;
 };
 const patch=async(sql:string,params:unknown[]=[])=>{
  await db.exec("reset role");await db.query(sql,[sid,...params]);await as(0);
 };
 const prepared=async()=>{
  await as(0);sid=await open("herbert");await act("peek");await act("ready");
  await as(1);await act("peek");await act("ready");await as(0);
 };
 await t.test("52 unique cards, four each, no secrets in public session",async()=>{
  const h=await secret();assert.equal(h.deck.length,43);assert.equal(h.discards.length,1);
  assert.equal(new Set([...h.deck,...h.discards,...Object.values(h.hands).flat()]).size,52);
  const s=await session();assert.equal(s.state.phase,"peek");
  assert.equal(s.state.hands,undefined);assert.equal(s.state.deck,undefined);assert.equal(s.state.drawn,undefined);
  assert.deepEqual(s.state.occupied[users[0]],[true,true,true,true]);
  assert.deepEqual(await view(),{drawn:null});
 });
 await t.test("one-time peek cannot be replayed, refreshed, or requested for partner",async()=>{
  const h=await secret();const id=randomUUID();
  const r=await act("peek",{user_id:users[1]},id);
  assert.deepEqual(r.peek,h.hands[users[0]].slice(2));
  assert.equal((await act("peek",{},id)).peek,undefined);
  await assert.rejects(()=>act("peek"),/bereits angesehen/);
  assert.deepEqual(await view(),{drawn:null});
  await assert.rejects(()=>generic(sid,0,"ready"),/Herbert/);
  await as(1);await assert.rejects(()=>act("ready"),/zuerst/);
  const second=await act("peek");assert.deepEqual(second.peek,h.hands[users[1]].slice(2));
  await act("ready");assert.equal((await session()).status,"lobby");
  await as(0);await act("ready");assert.equal((await session()).status,"playing");
 });
 await t.test("authorization, direct private access and forged actions",async()=>{
  await assert.rejects(()=>db.query("select * from private.herbert_games"),/permission denied/);
  await assert.rejects(()=>db.query("select private.herbert_publish($1,'forged')",[sid]),/permission denied/);
  await assert.rejects(()=>db.query("update public.game_sessions set status='finished' where id=$1",[sid]),/permission denied/);
  await as(2);await assert.rejects(()=>db.query("select public.herbert_view($1)",[sid]),/nicht verfügbar/);
  await assert.rejects(()=>db.query("select public.herbert_action($1,$2,0,'draw','{}')",[sid,randomUUID()]),/nicht verfügbar/);
  await as(1);await assert.rejects(()=>act("draw"),/nicht am Zug/);await as(0);
 });
 await t.test("draw private to active player, duplicate draw applies once; discard ends turn",async()=>{
  const before=await secret(),id=randomUUID(),rev=(await session()).revision;
  await Promise.all([act("draw",{},id,rev),act("draw",{},id,rev)]);
  assert.equal((await view()).drawn,before.deck[0]);
  await as(1);assert.deepEqual(await view(),{drawn:null});await as(0);
  await assert.rejects(()=>act("draw"),/zuerst/);
  await assert.rejects(()=>act("call"),/zuerst/);
  await act("discard");const s=await session();
  assert.equal(s.state.discard,before.deck[0]);assert.equal(s.state.turn_user,users[1]);assert.deepEqual(await view(),{drawn:null});
  const h=await secret();assert.equal(h.deck.length,before.deck.length-1);
 });
 await t.test("swap replaces exactly own selected card, rejects empty/out-of-range and stale moves",async()=>{
  await as(1);await act("draw");const newCard=(await view()).drawn;
  const old=await secret();await as(1);
  for(const position of [-1,4,99])await assert.rejects(()=>act("swap",{position}),/belegten/);
  await act("swap",{position:2,user_id:users[0]});
  const s=await session();assert.equal(s.state.discard,old.hands[users[1]][2]);assert.equal(s.state.turn_user,users[0]);
  const after=await secret();assert.equal(after.hands[users[1]][2],newCard);assert.deepEqual(after.hands[users[0]],old.hands[users[0]]);
  await assert.rejects(()=>act("draw",{},randomUUID(),0),/Spielstand geändert/);
 });
 await t.test("matching ranks slap outside turn; mismatches unchanged, no penalty, throttled",async()=>{
  await patch("update private.herbert_games set hands=$2::jsonb,discards=array[4],phase='turn',turn_user=$3 where session_id=$1",
   [JSON.stringify({[users[0]]:[17,1,2,3],[users[1]]:[30,5,6,7]}),users[0]]);
  const old=await secret();
  const invalid=await act("slap",{position:1,rank:5});assert.equal(invalid.ok,false);
  assert.deepEqual((await secret()).hands,old.hands);
  assert.equal((await act("slap",{position:0,rank:5})).ok,false);
  await patch("update private.herbert_games set last_slap='{}' where session_id=$1");
  await as(1);await act("slap",{position:0,rank:5});
  await as(0);await act("slap",{position:0,rank:5});
  const h=await secret();assert.equal(h.hands[users[0]][0],null);assert.equal(h.hands[users[1]][0],null);
  assert.equal(h.turn_user,users[0]);assert.equal(h.discards.length,3);
  await act("draw");await assert.rejects(()=>act("swap",{position:0}),/belegten/);
  await act("discard");
 });
 await t.test("FERTIG permits exactly one opponent turn, keeps last slap window then reveals, red kings zero",async()=>{
  await prepared();
  await patch("update private.herbert_games set hands=$2::jsonb,deck=array[12,9,10],discards=array[3] where session_id=$1",
   [JSON.stringify({[users[0]]:[25,38,0,null],[users[1]]:[51,1,null,null]})]);
  await act("call");assert.equal((await session()).state.turn_user,users[1]);
  await assert.rejects(()=>act("draw"),/nicht am Zug/);
  await as(1);await assert.rejects(()=>act("call"),/bereits/);
  await act("draw");await act("discard");assert.equal((await session()).state.phase,"final_slaps");
  await act("slap",{position:0,rank:13});
  await assert.rejects(()=>act("draw"),/zuerst/);
  assert.equal((await act("settle")).ok,false);
  await patch("update private.herbert_games set finish_after=clock_timestamp()-interval '1 second' where session_id=$1");
  await act("settle");
  const s=await session();assert.equal(s.status,"finished");assert.deepEqual(s.state.scores,{[users[0]]:1,[users[1]]:2});
  assert.deepEqual(s.state.winners,[users[0]]);assert.equal(s.state.caller_correct,true);
  assert.equal(s.state.values[25],0);assert.equal(s.state.values[38],0);assert.equal(s.state.values[12],13);assert.equal(s.state.values[51],13);
  await assert.rejects(()=>act("slap",{position:0,rank:13}),/vorbei/);
 });
 await t.test("ties and incorrect caller computed by server",async()=>{
  await prepared();await patch("update private.herbert_games set hands=$2::jsonb,phase='final_slaps',caller=$3,finish_after=now()-interval '1 second' where session_id=$1",
   [JSON.stringify({[users[0]]:[0,null,null,null],[users[1]]:[13,null,null,null]}),users[0]]);
  await act("settle");assert.deepEqual((await session()).state.winners,users.slice(0,2));
  await prepared();await patch("update private.herbert_games set hands=$2::jsonb,phase='final_slaps',caller=$3,finish_after=now()-interval '1 second' where session_id=$1",
   [JSON.stringify({[users[0]]:[12,null,null,null],[users[1]]:[25,null,null,null]}),users[0]]);
  await act("settle");assert.equal((await session()).state.caller_correct,false);
 });
 await t.test("reshuffle preserves top discard and all cards; degenerate empty deck settles safely",async()=>{
  await prepared();await patch("update private.herbert_games set deck='{}',discards=array[10,11,12] where session_id=$1");
  await act("draw");const h=await secret();assert.deepEqual(h.discards,[12]);
  assert.deepEqual([...h.deck,h.drawn].sort(),[10,11]);
  await prepared();await patch("update private.herbert_games set deck='{}',discards=array[12] where session_id=$1");
  await act("draw");assert.equal((await session()).state.phase,"final_slaps");
 });
 await t.test("rematch deduplicates into new secret deal, old session cannot act",async()=>{
  const oldId=sid;
  const replay=async()=> (await db.query<{id:string}>("select public.replay_game($1) id",[oldId])).rows[0].id;
  const results=await Promise.all([replay(),replay()]);assert.equal(results[0],results[1]);assert.notEqual(results[0],oldId);
  await assert.rejects(()=>act("peek"),/nicht verfügbar/);
  sid=results[0];assert.equal((await session()).state.phase,"peek");assert.equal((await session()).ready.length,0);
  assert.equal((await act("peek")).peek?.length,2);
  assert.equal((await db.query<{id:string}>("select active_session_id id from public.rooms where id=$1",[room])).rows[0].id,sid);
 });
 await db.close();
});
