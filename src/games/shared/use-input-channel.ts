"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { getSupabase } from "@/lib/supabase";
import type { GamePlayer } from "./types";
/** Sender identity comes from the RLS-bound channel topic, never from a payload claim. */
export function useInputChannel(
  roomId: string,
  sessionId: string,
  players: GamePlayer[],
  userId: string,
  receive: (sender: string, payload: unknown) => void,
) {
  const receiver = useRef(receive);
  receiver.current = receive;
  const outgoing = useRef<RealtimeChannel | null>(null);
  const [connected, setConnected] = useState(false);
  const ids = players
    .map((p) => p.user_id)
    .sort()
    .join(",");
  useEffect(() => {
    let alive = true;
    setConnected(false);
    const db = getSupabase();
    const channels = ids
      .split(",")
      .filter(Boolean)
      .map((id) => {
        const channel = db.channel(
          `room:${roomId}:session:${sessionId}:input:${id}`,
          { config: { private: true, broadcast: { self: false, ack: true } } },
        );
        channel
          .on("broadcast", { event: "input" }, ({ payload }) => {
            if (alive) receiver.current(id, payload);
          })
          .subscribe((status) => {
            if (id === userId && alive) setConnected(status === "SUBSCRIBED");
          });
        if (id === userId) outgoing.current = channel;
        return channel;
      });
    return () => {
      alive = false;
      outgoing.current = null;
      for (const channel of channels) void db.removeChannel(channel);
    };
  }, [roomId, sessionId, ids, userId]);
  const send = useCallback((payload: unknown) => {
    if (outgoing.current)
      void outgoing.current.send({
        type: "broadcast",
        event: "input",
        payload,
      });
  }, []);
  return { send, connected };
}
