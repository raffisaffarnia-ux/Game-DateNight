import { createClient } from "@supabase/supabase-js";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

const clients = [0, 1].map(() => createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } }));
async function rpc(c, name, args = {}) {
  const r = await c.rpc(name, args);
  if (r.error) throw new Error(`${name}: ${r.error.message}`);
  return r.data;
}
const users = [];
try {
  for (const c of clients) {
    const r = await c.auth.signInAnonymously();
    if (r.error) throw r.error;
    users.push(r.data.user.id);
  }
  const room = await rpc(clients[0], "create_room", { player_name: "Herbert QA A" });
  const r = await clients[0].from("rooms").select("code").eq("id", room).single();
  if (r.error) throw r.error;
  await rpc(clients[1], "join_room", { invite_code: r.data.code, player_name: "Herbert QA B" });
  const id = await rpc(clients[0], "open_game", { target: room, game: "herbert", replay: true });
  async function read(c = clients[0]) {
    const r = await c.from("game_sessions").select("state,revision").eq("id", id).single();
    if (r.error) throw r.error;
    return r.data;
  }
  async function act(i, action, payload = {}) {
    return rpc(clients[i], "herbert_action", { target: id, request_id: randomUUID(), expected_revision: (await read()).revision, action, payload });
  }
  for (const i of [0, 1]) { await act(i, "peek"); await act(i, "ready"); }
  const top = (await read()).state.discard;
  await act(0, "draw");
  const drawn = (await read()).state.drawn;
  await act(0, "discard");
  await act(1, "take_discard");
  let s = await read();
  assert.equal(s.state.drawn, drawn);
  assert.equal(s.state.discard, top);
  assert.equal(s.state.draw_source, "discard");
  assert.deepEqual(s.state, (await read(clients[1])).state);
  await act(1, "swap", { position: 0 });
  s = await read();
  const wait = Math.max(0, Date.parse(s.state.turn_deadline) - Date.now() + 300);
  assert.ok(wait < 22000);
  await new Promise(resolve => setTimeout(resolve, wait));
  await act(1, "timeout");
  assert.equal((await read()).state.turn_user, users[1]);
  await act(1, "call");
  await act(0, "draw");
  await act(0, "discard");
  await new Promise(resolve => setTimeout(resolve, 2200));
  await act(0, "settle");
  s = await read();
  assert.equal(s.state.phase, "finished");
  assert.equal(s.state.hands[users[1]][0], drawn);
  await act(0, "next_round");
  assert.equal((await read()).state.round_no, 2);
  console.log(JSON.stringify({ result: "PASS", realDiscardStack: true, discardSwap: true, deadline20Seconds: true, twoClientsAgree: true, nextRound: true }));
} finally {
  if (users[0]) await rpc(clients[0], "close_my_rooms");
  for (const c of clients) await c.auth.signOut();
}
