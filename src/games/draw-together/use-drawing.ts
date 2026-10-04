"use client";
import { useEffect, useRef, useState } from "react";
import { getSupabase } from "@/lib/supabase";
import type { GameViewProps } from "../shared/types";
import { useInputChannel } from "../shared/use-input-channel";
import type { Stroke } from "./types";
export function useDrawing({
  session,
  players,
  userId,
  connected,
}: GameViewProps) {
  const [strokes, setStrokes] = useState<Stroke[]>([]);
  const [live, setLive] = useState<Record<string, Stroke>>({});
  const [error, setError] = useState("");
  const version = session.state.canvas_version || 0;
  const committed = useRef(new Set<string>());
  const refreshRef = useRef<() => Promise<void>>(async () => {});
  const realtime = useInputChannel(
    session.room_id,
    session.id,
    players,
    userId,
    (sender, payload) => {
      const p = payload as {
        round?: number;
        version?: number;
        stroke?: Stroke;
      };
      const s = p?.stroke;
      const artist = players.find(
        (x) => x.seat === (session.round % 2) + 1,
      )?.user_id;
      if (
        p?.round !== session.round ||
        p.version !== version ||
        !s ||
        typeof s.id !== "string" ||
        committed.current.has(s.id) ||
        session.status !== "playing" ||
        (session.state.mode === "guess" && sender !== artist)
      )
        return;
      if (
        !Array.isArray(s.stroke?.points) ||
        s.stroke.points.length > 512 ||
        !s.stroke.points.every(
          (p) =>
            Number.isFinite(p.x) &&
            Number.isFinite(p.y) &&
            p.x >= 0 &&
            p.x <= 1 &&
            p.y >= 0 &&
            p.y <= 1,
        ) ||
        !/^#[0-9a-f]{6}$/i.test(s.stroke.color) ||
        !Number.isFinite(s.stroke.width) ||
        s.stroke.width < 0.001 ||
        s.stroke.width > 0.05 ||
        !["pen", "eraser"].includes(s.stroke.tool)
      )
        return;
      setLive((previous) => ({
        ...previous,
        [sender]: { ...s, user_id: sender },
      }));
    },
  );
  useEffect(() => {
    let active = true;
    let pending = false;
    let again = false;
    const db = getSupabase();
    committed.current = new Set();
    setStrokes([]);
    setLive({});
    const refresh = async () => {
      if (pending) {
        again = true;
        return;
      }
      pending = true;
      try {
        do {
          again = false;
          const rows: Stroke[] = [];
          for (let offset = 0; offset < 2000; offset += 500) {
            const { data, error } = await db
              .from("drawing_strokes")
              .select("*")
              .eq("session_id", session.id)
              .eq("round", session.round)
              .eq("canvas_version", version)
              .order("sequence")
              .range(offset, offset + 499);
            if (error) throw error;
            rows.push(...(data as Stroke[]));
            if (data.length < 500) break;
          }
          if (!active) return;
          committed.current = new Set(rows.map((s) => s.id));
          setStrokes(rows.filter((s) => !s.removed));
          setLive((previous) =>
            Object.fromEntries(
              Object.entries(previous).filter(
                ([, s]) => !committed.current.has(s.id),
              ),
            ),
          );
          setError("");
        } while (again && active);
      } catch {
        if (active) setError("Drawing could not be restored. Retrying…");
      } finally {
        pending = false;
      }
    };
    refreshRef.current = refresh;
    const channel = db
      .channel(`room:${session.room_id}:session:${session.id}:strokes`, {
        config: { private: true },
      })
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "drawing_strokes",
          filter: `session_id=eq.${session.id}`,
        },
        () => void refresh(),
      )
      .subscribe((s) => {
        if (s === "SUBSCRIBED") void refresh();
      });
    void refresh();
    const timer = setInterval(() => {
      setLive({});
      void refresh();
    }, 5000);
    return () => {
      active = false;
      clearInterval(timer);
      void db.removeChannel(channel);
    };
  }, [session.id, session.room_id, session.round, version]);
  function preview(stroke: Stroke) {
    setLive((p) => ({ ...p, [userId]: stroke }));
    realtime.send({ round: session.round, version, stroke });
  }
  async function commit(stroke: Stroke) {
    const { error } = await getSupabase().rpc("commit_stroke", {
      target: session.id,
      expected_round: session.round,
      canvas_version: version,
      stroke_id: stroke.id,
      stroke: stroke.stroke,
    });
    if (error) {
      setError(
        "This stroke was not saved. Check your connection and draw it again.",
      );
      setLive((p) =>
        Object.fromEntries(
          Object.entries(p).filter(([, s]) => s.id !== stroke.id),
        ),
      );
    } else await refreshRef.current();
  }
  async function undo() {
    const { error } = await getSupabase().rpc("undo_stroke", {
      target: session.id,
      expected_round: session.round,
    });
    if (error) setError("Undo could not be saved. Try again.");
    else await refreshRef.current();
  }
  return {
    strokes: [...strokes, ...Object.values(live)],
    preview,
    commit,
    undo,
    error,
    connected: connected && realtime.connected,
    version,
  };
}
