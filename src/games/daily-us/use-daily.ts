"use client";
import { useEffect, useRef, useState } from "react";
import { getSupabase } from "@/lib/supabase";
type Context = {
  pair_id: string;
  day: string;
  timezone: string;
  entry_id: string;
  streak: number;
};
export type DailyEntry = {
  id: string;
  day: string;
  question_id: string;
  revealed: boolean;
};
export type DailyAnswer = { entry_id: string; user_id: string; value: string };
export function useDaily(roomId: string) {
  const [context, setContext] = useState<Context | null>(null);
  const [entries, setEntries] = useState<DailyEntry[]>([]);
  const [answers, setAnswers] = useState<DailyAnswer[]>([]);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [limit, setLimit] = useState(60);
  const [attempt, setAttempt] = useState(0);
  const refreshRef = useRef<() => Promise<void>>(async () => {});
  useEffect(() => {
    let active = true;
    let refreshing = false;
    const db = getSupabase();
    let channel: ReturnType<typeof db.channel> | undefined;
    const refresh = async () => {
      if (refreshing) return;
      refreshing = true;
      try {
        const c = await db.rpc("daily_context", { target: roomId });
        if (c.error) throw c.error;
        const ctx = c.data as Context;
        if (!active) return;
        setContext(ctx);
        const entries: DailyEntry[] = [],
          answers: DailyAnswer[] = [];
        for (let offset = 0; offset < limit; offset += 60) {
          const e = await db
            .from("daily_entries")
            .select("*")
            .eq("pair_id", ctx.pair_id)
            .order("day", { ascending: false })
            .range(offset, offset + 59);
          if (e.error) throw e.error;
          entries.push(...e.data);
          if (e.data.length) {
            const a = await db
              .from("daily_answers")
              .select("*")
              .in(
                "entry_id",
                e.data.map((x) => x.id),
              );
            if (a.error) throw a.error;
            answers.push(...a.data);
          }
          if (e.data.length < 60) break;
        }
        if (active) {
          setEntries(entries);
          setAnswers(answers);
          setError("");
        }
        if (!channel && active) {
          channel = db
            .channel(`room:${roomId}:daily`, {
              config: {
                private: true,
                postgres_changes_options: { wait: true },
              },
            })
            .on(
              "postgres_changes",
              {
                event: "*",
                schema: "public",
                table: "daily_entries",
                filter: `pair_id=eq.${ctx.pair_id}`,
              },
              () => void refresh(),
            )
            .subscribe((status) => {
              if (status === "SUBSCRIBED") void refresh();
            });
        }
      } catch (error) {
        if (active)
          setError(
            error &&
              typeof error === "object" &&
              "message" in error &&
              String(error.message).startsWith("No unseen questions remain")
              ? "You’ve seen every available daily question. Fresh cards need to be added."
              : "Could not load your daily question. Try again.",
          );
      } finally {
        refreshing = false;
      }
    };
    refreshRef.current = refresh;
    void refresh();
    const timer = setInterval(() => void refresh(), 10000);
    const visible = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    document.addEventListener("visibilitychange", visible);
    return () => {
      active = false;
      clearInterval(timer);
      document.removeEventListener("visibilitychange", visible);
      if (channel) void db.removeChannel(channel);
    };
  }, [roomId, limit, attempt]);
  async function submit(value: string) {
    if (!context) return false;
    setBusy(true);
    try {
      const { error } = await getSupabase().rpc("daily_submit", {
        target: context.entry_id,
        answer: value,
      });
      if (error) throw error;
      await refreshRef.current();
      return true;
    } catch {
      setError(
        "Could not save your answer. The day may have changed; refresh and try again.",
      );
      return false;
    } finally {
      setBusy(false);
    }
  }
  return {
    context,
    entries,
    answers,
    error,
    busy,
    submit,
    retry: () => setAttempt((n) => n + 1),
    more: () => setLimit((n) => n + 60),
    canLoadMore: entries.length === limit,
  };
}
