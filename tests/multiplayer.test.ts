import test from "node:test";
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
test(
  "real database enforces capacity, isolation and shared selection",
  { skip: !url || !key || url.includes("your-project") },
  async () => {
    const clients = Array.from({ length: 4 }, () =>
      createClient(url!, key!, {
        auth: { persistSession: false, autoRefreshToken: false },
      }),
    );
    for (const c of clients) {
      const { error } = await c.auth.signInAnonymously();
      assert.ifError(error);
    }
    const [host, a, b, stranger] = clients;
    const created = await host.rpc("create_room", { player_name: "Host" });
    assert.ifError(created.error);
    const id = created.data;
    const room = await host.from("rooms").select("*").eq("id", id).single();
    assert.ifError(room.error);
    const joined = await Promise.all(
      [a, b].map((c) =>
        c.rpc("join_room", {
          invite_code: room.data.code,
          player_name: "Partner",
        }),
      ),
    );
    assert.equal(joined.filter((r) => !r.error).length, 1);
    const winner = joined[0].error ? b : a;
    const outsider = await stranger.from("rooms").select("*").eq("id", id);
    assert.ifError(outsider.error);
    assert.equal(outsider.data?.length, 0);
    const direct = await stranger.from("room_members").insert({
      room_id: id,
      user_id: (await stranger.auth.getUser()).data.user!.id,
      name: "Intruder",
      seat: 2,
    });
    assert.ok(direct.error);
    assert.ok(
      (await host.rpc("select_game", { target: id, game: "invalid" })).error,
    );
    assert.ok(
      (await stranger.rpc("select_game", { target: id, game: "this-or-that" }))
        .error,
    );
    assert.ifError(
      (await host.rpc("select_game", { target: id, game: "this-or-that" }))
        .error,
    );
    const selected = await winner
      .from("rooms")
      .select("current_game")
      .eq("id", id)
      .single();
    assert.equal(selected.data?.current_game, "this-or-that");
    const rejoin = await winner.rpc("join_room", {
      invite_code: room.data.code,
      player_name: "Partner",
    });
    assert.ifError(rejoin.error);
    assert.equal(rejoin.data, id);
    for (const c of clients) await c.auth.signOut();
  },
);
