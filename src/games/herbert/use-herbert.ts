"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { getSupabase } from "@/lib/supabase";
import type { GameViewProps } from "../shared/types";
import type { CardId, HerbertAction, HerbertState } from "./types";

export function useHerbert(p: GameViewProps) {
  const state = p.session.state as unknown as HerbertState;
  const [peek, setPeek] = useState<{ round: number; cards: CardId[] } | null>(
    null,
  );
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const pending = useRef(false);
  const latest = useRef(p);
  latest.current = p;
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);
  useEffect(() => {
    const hide = () => {
      if (document.hidden) setPeek(null);
    };
    document.addEventListener("visibilitychange", hide);
    return () => document.removeEventListener("visibilitychange", hide);
  }, []);
  const act = useCallback(
    async (action: HerbertAction, payload: Record<string, unknown> = {}) => {
      const current = latest.current;
      if (pending.current || !current.connected) return false;
      pending.current = true;
      setBusy(true);
      setMessage("");
      if (action === "ready") setPeek(null);
      const request = {
        target: current.session.id,
        request_id: crypto.randomUUID(),
        expected_revision: current.session.revision,
        action,
        payload,
      };
      try {
        const { data, error } = await getSupabase().rpc(
          "herbert_action",
          request,
        );
        if (error) throw error;
        if (mounted.current && data?.peek)
          setPeek({
            round: (current.session.state as unknown as HerbertState).round_no,
            cards: data.peek,
          });
        if (mounted.current && data?.message) setMessage(data.message);
        await latest.current.refresh?.();
        return data?.ok === true;
      } catch (error) {
        if (mounted.current)
          setMessage(
            error && typeof error === "object" && "message" in error
              ? String(error.message)
              : "Verbindung unterbrochen. Lade den Spielstand erneut.",
          );
        await latest.current.refresh?.();
        return false;
      } finally {
        pending.current = false;
        if (mounted.current) setBusy(false);
      }
    },
    [],
  );
  useEffect(() => {
    if (state.phase !== "final_slaps" || !p.connected) return;
    const timer = setInterval(() => void act("settle"), 700);
    return () => clearInterval(timer);
  }, [state.phase, p.connected, act]);
  return {
    state,
    drawn: state.drawn ?? null,
    peek:
      state.phase === "peek" &&
      !p.session.ready.includes(p.userId) &&
      peek?.round === state.round_no
        ? peek.cards
        : null,
    busy: busy || p.busy,
    message,
    act,
  };
}
