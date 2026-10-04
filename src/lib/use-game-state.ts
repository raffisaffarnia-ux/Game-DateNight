"use client";

import { useEffect, useState } from "react";
import { getSupabase, identity } from "./supabase";

/** Read-only shared state adapter. Each game owns its validated move RPC. */
export function useGameState<T>(roomId: string, gameId: string) {
  const [snapshot, setSnapshot] = useState<{
    state: T;
    revision: number;
  } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    let cleanup = () => {};
    setSnapshot(null);
    setLoading(true);
    setError(null);

    (async () => {
      await identity();
      if (cancelled) return;
      const db = getSupabase();
      const refresh = async () => {
        const { data, error } = await db
          .from("game_states")
          .select("state,revision")
          .eq("room_id", roomId)
          .eq("game_id", gameId)
          .maybeSingle();
        if (cancelled) return;
        if (error) setError(error.message);
        else {
          setError(null);
          setSnapshot((previous) =>
            data && (!previous || data.revision >= previous.revision)
              ? { state: data.state as T, revision: data.revision }
              : previous,
          );
        }
        setLoading(false);
      };
      const channel = db
        .channel(`room:${roomId}:game:${gameId}`, { config: { private: true } })
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "game_states",
            filter: `room_id=eq.${roomId}`,
          },
          () => void refresh(),
        )
        .subscribe((status) => {
          if (status === "SUBSCRIBED") void refresh();
          else if (status === "CHANNEL_ERROR" && !cancelled)
            setError("Reconnecting to your game…");
        });
      const timer = setInterval(() => void refresh(), 15000);
      cleanup = () => {
        clearInterval(timer);
        void db.removeChannel(channel);
      };
      await refresh();
    })().catch((error) => {
      if (!cancelled) {
        setError(error.message);
        setLoading(false);
      }
    });

    return () => {
      cancelled = true;
      cleanup();
    };
  }, [roomId, gameId]);

  return { snapshot, loading, error };
}

