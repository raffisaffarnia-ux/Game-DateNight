import { createClient } from "@supabase/supabase-js";
import assert from "node:assert/strict";
const clients = [0,1].map(()=>createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}}));
async function rpc(c,name,args){const r=await c.rpc(name,args);if(r.error)throw new Error(name+": "+r.error.message);return r.data;}
const users=[];
for(const c of clients){const r=await c.auth.signInAnonymously();if(r.error)throw r.error;users.push(r.data.user.id);}
const room=await rpc(clients[0],"create_room",{player_name:"Design QA A"});
const roomData=await clients[0].from("rooms").select("code").eq("id",room).single();if(roomData.error)throw roomData.error;
await rpc(clients[1],"join_room",{invite_code:roomData.data.code,player_name:"Design QA B"});
const id=await rpc(clients[0],"open_game",{target:room,game:"dots-and-dates",replay:true});
for(const c of clients)await rpc(c,"game_action",{target:id,expected_round:0,action:"ready",payload:{}});
async function read(c=clients[0]){const r=await c.from("game_sessions").select("*").eq("id",id).single();if(r.error)throw r.error;return r.data;}
let prompts=0, extras=0;
for(let edge=0;edge<40;edge++){
 let s=await read();
 while(s.state.phase==="prompt"){prompts++;await rpc(clients[0],"dots_action",{target:id,expected_revision:s.revision,action:"dismiss_prompt",payload:{prompt_id:s.state.active_prompt}});s=await read();}
 const who=users.indexOf(s.state.turn_user_id);assert.ok(who>=0);
 const before=s.state.boxes.filter(Boolean).length;
 await rpc(clients[who],"dots_action",{target:id,expected_revision:s.revision,action:"move",payload:{edge}});
 const after=await read();const partner=await read(clients[1]);assert.deepEqual(after.state,partner.state);
 if(after.state.boxes.filter(Boolean).length>before){extras++;assert.equal(after.state.turn_user_id,users[who]);}
 if(edge===0){const r=await clients[1].rpc("dots_action",{target:id,expected_revision:after.revision,action:"move",payload:{edge:0}});assert.ok(r.error);}
}
let s=await read();while(s.state.phase==="prompt"){prompts++;await rpc(clients[0],"dots_action",{target:id,expected_revision:s.revision,action:"dismiss_prompt",payload:{prompt_id:s.state.active_prompt}});s=await read();}
assert.equal(s.status,"finished");assert.equal(s.state.boxes.filter(Boolean).length,16);assert.equal(Object.values(s.state.scores).reduce((a,b)=>a+b,0),16);
assert.equal(prompts,16);
const replay=await rpc(clients[0],"replay_game",{target:id});assert.ok(replay);
console.log(JSON.stringify({result:"PASS",moves:40,completedBoxes:16,conversationCards:prompts,extraTurns:extras,twoClientsAgree:true,replay:true}));
await rpc(clients[0],"close_my_rooms",{});
for(const c of clients)await c.auth.signOut();
