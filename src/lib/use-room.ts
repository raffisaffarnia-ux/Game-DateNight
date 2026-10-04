"use client";
import { useEffect, useRef, useState } from "react";
import { getSupabase, identity } from "./supabase";
import { roomError } from "./room-error";
export type Room = {
  id: string;
  code: string;
  current_game: string | null;
  active_session_id: string | null;
  pair_id: string | null;
  expires_at: string;
};
export type Member = { user_id: string; name: string; seat: number };
export function useRoom(id: string) {
  const [room, setRoom] = useState<Room | null>(null);
  const [members, setMembers] = useState<Member[]>([]);
  const [online, setOnline] = useState<string[]>([]);
  const [userId, setUserId] = useState("");
  const [error, setError] = useState("");
  const [status, setStatus] = useState("Connecting");
  const [attempt, setAttempt] = useState(0);
  const refreshRoom = useRef<(() => Promise<void>) | null>(null);
  useEffect(() => {
    let disposed = false;
    let cleanup = () => {};
    setError("");
    setStatus("Connecting");
    setRoom((previous) => (previous?.id === id ? previous : null));
    setOnline([]);
    (async () => {
      const uid = await identity();
      if (disposed) return;
      setUserId(uid);
      const db = getSupabase();
      const resumed = await db.rpc("resume_room", { target: id });
      if (resumed.error)
        throw new Error(
          "This room could not be restored. Reconnect using the browser you joined with.",
        );
      let presenceConnected = false;
      let refreshVersion = 0;
      const refresh = async () => {
        const version = ++refreshVersion;
        try {
          const [r, m] = await Promise.all([
            db.from("rooms").select("*").eq("id", id).single(),
            db
              .from("room_members")
              .select("user_id,name,seat")
              .eq("room_id", id)
              .order("seat"),
          ]);
          if (disposed || version !== refreshVersion) return;
          if (r.error || m.error) {
            setStatus("Reconnecting");
            setError(
              "Your room could not be loaded. Check your connection and retry.",
            );
            return;
          }
          setRoom(r.data);
          setMembers(m.data);
          setError("");
          if (presenceConnected) setStatus("Connected");
        } catch {
          if (!disposed && version === refreshVersion) {
            setStatus("Reconnecting");
            setError("Your connection was interrupted. Please retry.");
          }
        }
      };
      refreshRoom.current = refresh;
      await refresh();
      if (disposed) return;
      await db.realtime.setAuth();
      if (disposed) return;
      const channel = db.channel(`room:${id}`, {
        config: {
          private: true,
          presence: { key: uid },
          postgres_changes_options: { wait: true },
        },
      });
      channel
        .on("presence", { event: "sync" }, () => {
          if (!disposed) setOnline(Object.keys(channel.presenceState()));
        })
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "rooms",
            filter: `id=eq.${id}`,
          },
          () => void refresh(),
        )
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "room_members",
            filter: `room_id=eq.${id}`,
          },
          () => void refresh(),
        )
        .subscribe(async (state) => {
          if (disposed) return;
          if (state === "SUBSCRIBED") {
            const tracked = await channel.track({
              online_at: new Date().toISOString(),
            });
            if (disposed) return;
            presenceConnected = tracked === "ok";
            setStatus(tracked === "ok" ? "Connected" : "Reconnecting");
            void refresh();
          } else if (["CHANNEL_ERROR", "TIMED_OUT", "CLOSED"].includes(state)) {
            presenceConnected = false;
            setStatus("Reconnecting");
            setOnline([]);
          }
        });
      // A slow reconciliation protects against missed events and detects room expiry.
      const timer = setInterval(() => void refresh(), 15000);
      const offline = () => {
        presenceConnected = false;
        setStatus("Offline");
        setOnline([]);
      };
      const reconnect = () => {
        void refresh();
      };
      window.addEventListener("offline", offline);
      window.addEventListener("online", reconnect);
      cleanup = () => {
        clearInterval(timer);
        window.removeEventListener("offline", offline);
        window.removeEventListener("online", reconnect);
        void db.removeChannel(channel);
      };
    })().catch((e) => {
      if (!disposed) setError(roomError(e));
    });
    return () => {
      disposed = true;
      refreshRoom.current = null;
      cleanup();
    };
  }, [id, attempt]);
  async function selectGame(game: string | null) {
    const { error } = await getSupabase().rpc("select_game", {
      target: id,
      game,
    });
    if (error)
      throw new Error(
        error.message.startsWith("No unseen questions remain")
          ? "You’ve played every available question for this game. Fresh cards need to be added before another round."
          : "Could not open the game. Check your connection and try again.",
      );
    await refreshRoom.current?.();
  }
  return {
    room,
    members,
    online,
    userId,
    error,
    status,
    selectGame,
    retry: () => setAttempt((v) => v + 1),
  };
}
