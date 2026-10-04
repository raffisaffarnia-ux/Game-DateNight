"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { getSupabase } from "@/lib/supabase";
import type { Answer, GameAction, GameSession } from "./types";

export function useSession(roomId: string, sessionId: string) {
  const [session, setSession] = useState<GameSession | null>(null);
  const [answers, setAnswers] = useState<Answer[]>([]);
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [attempt, retry] = useState(0);
  const refreshRef = useRef<() => Promise<void>>(async () => {});
  const snapshot = useRef<GameSession | null>(null);

  useEffect(() => {
    let disposed = false;
    let pending = false;
    let again = false;
    const db = getSupabase();
    setSession(null);
    snapshot.current = null;
    setAnswers([]);
    setError("");
    const refresh = async () => {
      if (pending) {
        again = true;
        return;
      }
      pending = true;
      try {
        do {
          again = false;
          const s = await db
            .from("game_sessions")
            .select("*")
            .eq("id", sessionId)
            .single();
          if (s.error) throw s.error;
          const a = await db
            .from("game_answers")
            .select("*")
            .eq("session_id", sessionId)
            .order("round");
          if (a.error) throw a.error;
          if (
            !disposed &&
            (!snapshot.current || s.data.revision >= snapshot.current.revision)
          ) {
            snapshot.current = s.data as GameSession;
            setSession(snapshot.current);
            setAnswers(a.data as Answer[]);
            setError("");
          }
        } while (again && !disposed);
      } catch {
        if (!disposed)
          setError(
            "Could not restore this game. Check your connection and retry.",
          );
      } finally {
        pending = false;
      }
    };
    refreshRef.current = refresh;
    const channel = db
      .channel(`room:${roomId}:session:${sessionId}:changes`, {
        config: { private: true, postgres_changes_options: { wait: true } },
      })
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "game_sessions",
          filter: `id=eq.${sessionId}`,
        },
        () => void refresh(),
      )
      .subscribe((status) => {
        if (disposed) return;
        setConnected(status === "SUBSCRIBED");
        if (status === "SUBSCRIBED") void refresh();
      });
    void refresh();
    const timer = setInterval(() => void refresh(), 5000);
    const visible = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    window.addEventListener("online", refresh);
    document.addEventListener("visibilitychange", visible);
    return () => {
      disposed = true;
      clearInterval(timer);
      window.removeEventListener("online", refresh);
      document.removeEventListener("visibilitychange", visible);
      void db.removeChannel(channel);
    };
  }, [roomId, sessionId, attempt]);

  const command = useCallback(
    async (action: GameAction, payload: Record<string, unknown> = {}) => {
      const current = snapshot.current;
      if (!current) return false;
      setBusy(true);
      setError("");
      try {
        const { error } = await getSupabase().rpc("game_action", {
          target: sessionId,
          expected_round: current.round,
          action,
          payload,
        });
        if (error) throw error;
        await refreshRef.current();
        return true;
      } catch (error) {
        await refreshRef.current();
        setError(
          error &&
            typeof error === "object" &&
            "message" in error &&
            String(error.message).startsWith("No unseen questions remain")
            ? current.game_type === "deep-talk"
              ? "You’ve played every card in this deck. Choose another deck for fresh questions."
              : "You’ve played every available prompt. Fresh cards need to be added before another round."
            : "That action could not be saved. Refresh the game state and try again.",
        );
        return false;
      } finally {
        setBusy(false);
      }
    },
    [sessionId],
  );
  return {
    session,
    answers,
    connected,
    error,
    busy,
    command,
    refresh: () => refreshRef.current(),
    retry: () => retry((n) => n + 1),
  };
}
