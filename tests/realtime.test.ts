import test from "node:test";
import assert from "node:assert/strict";
import { createClient, type RealtimeChannel } from "@supabase/supabase-js";
const url = process.env.NEXT_PUBLIC_SUPABASE_URL,
  key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
async function until(check: () => boolean, timeout = 12000) {
  const start = Date.now();
  while (!check()) {
    if (Date.now() - start > timeout)
      throw new Error("Realtime event was not delivered");
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}
async function subscribe(channel: RealtimeChannel) {
  return new Promise<void>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error("Subscription timed out")),
      25000,
    );
    channel.subscribe((status, error) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timer);
        resolve();
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timer);
        reject(
          new Error(
            `${channel.topic}: ${status}: ${error?.message ?? "No details"}`,
          ),
        );
      }
    });
  });
}
test(
  "live Supabase synchronizes presence, private answers and authenticated broadcasts",
  { skip: !url || !key || url.includes("your-project"), timeout: 60000 },
  async () => {
    const clients = [0, 1].map(() =>
      createClient(url!, key!, {
        auth: { persistSession: false, autoRefreshToken: false },
      }),
    );
    try {
      const users: string[] = [];
      for (const c of clients) {
        const result = await c.auth.signInAnonymously();
        assert.ifError(result.error);
        users.push(result.data.user!.id);
        await c.realtime.setAuth(result.data.session!.access_token);
      }
      const [a, b] = clients;
      const created = await a.rpc("create_room", { player_name: "Realtime A" });
      assert.ifError(created.error);
      const room = created.data;
      const r = await a.from("rooms").select("code").eq("id", room).single();
      assert.ifError(r.error);
      assert.ifError(
        (
          await b.rpc("join_room", {
            invite_code: r.data!.code,
            player_name: "Realtime B",
          })
        ).error,
      );
      const presence = clients.map((c, i) =>
        c.channel(`room:${room}`, {
          config: { private: true, presence: { key: users[i], enabled: true } },
        }),
      );
      await Promise.all(presence.map(subscribe));
      await Promise.all(
        presence.map((c) => c.track({ online_at: new Date().toISOString() })),
      );
      await until(() =>
        presence.every((c) => Object.keys(c.presenceState()).length === 2),
      );
      const opened = await a.rpc("open_game", {
        target: room,
        game: "this-or-that",
      });
      assert.ifError(opened.error);
      const session = opened.data;
      let revision = 0;
      const changes = b
        .channel(`room:${room}:session:${session}:test`, {
          config: { private: true, postgres_changes_options: { wait: true } },
        })
        .on(
          "postgres_changes",
          {
            event: "UPDATE",
            schema: "public",
            table: "game_sessions",
            filter: `id=eq.${session}`,
          },
          ({ new: row }) => {
            revision = Number(row.revision);
          },
        );
      await subscribe(changes);
      for (const c of clients)
        assert.ifError(
          (
            await c.rpc("game_action", {
              target: session,
              expected_round: 0,
              action: "ready",
            })
          ).error,
        );
      assert.ifError(
        (
          await a.rpc("game_action", {
            target: session,
            expected_round: 0,
            action: "answer",
            payload: { value: "A" },
          })
        ).error,
      );
      const hidden = await b
        .from("game_answers")
        .select("*")
        .eq("session_id", session);
      assert.ifError(hidden.error);
      assert.equal(hidden.data!.length, 0);
      assert.ifError(
        (
          await b.rpc("game_action", {
            target: session,
            expected_round: 0,
            action: "answer",
            payload: { value: "A" },
          })
        ).error,
      );
      await until(() => revision >= 4);
      const revealed = await a
        .from("game_answers")
        .select("*")
        .eq("session_id", session);
      assert.equal(revealed.data!.length, 2);
      assert.ok(revealed.data!.every((x) => x.revealed));
      let received = false;
      const topic = `room:${room}:session:${session}:input:${users[0]}`;
      const sender = a.channel(topic, {
        config: { private: true, broadcast: { ack: true } },
      });
      const receiver = b
        .channel(topic, { config: { private: true } })
        .on("broadcast", { event: "input" }, ({ payload }) => {
          received = payload.test === "hello";
        });
      await Promise.all([subscribe(sender), subscribe(receiver)]);
      assert.equal(
        await sender.send({
          type: "broadcast",
          event: "input",
          payload: { test: "hello" },
        }),
        "ok",
      );
      await until(() => received);
      await b.removeChannel(presence[1]);
      await until(() => Object.keys(presence[0].presenceState()).length === 1);
      const restored = await b
        .from("game_sessions")
        .select("status,state")
        .eq("id", session)
        .single();
      assert.equal(restored.data?.status, "round_end");
      assert.equal(restored.data?.state.matches, 1);
    } finally {
      for (const c of clients) {
        await c.removeAllChannels();
        await c.auth.signOut();
      }
    }
  },
);
