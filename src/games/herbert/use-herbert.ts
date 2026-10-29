"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { getSupabase } from "@/lib/supabase";
import type { GameViewProps } from "../shared/types";
import type { CardId, HerbertAction, HerbertState } from "./types";

export function useHerbert(p: GameViewProps) {
  const state = p.session.state as unknown as HerbertState;
  const [privateDraw, setPrivateDraw] = useState<{ session: string; revision: number; card: CardId | null } | null>(null);
  useEffect(() => {
    if (state.phase !== "drawn" || state.turn_user !== p.userId) { setPrivateDraw(null); return; }
    let active = true;
    const session = p.session.id, revision = p.session.revision;
    const load = async () => {
      const {data, error} = await getSupabase().rpc("herbert_view", { target: session });
      if (active && !error) setPrivateDraw({session, revision, card:data?.drawn ?? null});
    };
    void load();
    const retry = setInterval(() => void load(), 2500);
    return () => { active = false; clearInterval(retry); };
  }, [p.session.id, p.session.revision, p.userId, state.phase, state.turn_user]);
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
      if (["ready", "draw", "call", "next_round"].includes(action))
        setPeek(null);
      const request = {
        target: current.session.id,
        request_id: crypto.randomUUID(),
        expected_revision: current.session.revision,
        action,
        payload,
      };
      try {
        // FERTIG is legal even off-turn. A partner becoming ready or moving must
        // not silently reject the confirmation because its displayed revision lags.
        if (action === "call") {
          const { data: fresh, error: readError } = await getSupabase()
            .from("game_sessions").select("revision,state").eq("id", request.target).single();
          if (readError) throw readError;
          if (fresh.state.round_no !== (current.session.state as unknown as HerbertState).round_no)
            throw new Error("Eine neue Runde hat begonnen. Bitte prüfe deine Karten.");
          request.expected_revision = fresh.revision;
        }
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
  useEffect(() => {
    if (!state.turn_deadline || !p.connected || !["turn", "drawn"].includes(state.phase)) return;
    const timer = setInterval(() => {
      if (Date.now() >= Date.parse(state.turn_deadline!)) void act("timeout");
    }, 500);
    return () => clearInterval(timer);
  }, [state.turn_deadline, state.phase, p.connected, act]);
  return {
    state,
    drawn: privateDraw?.session === p.session.id && privateDraw.revision === p.session.revision && state.turn_user === p.userId && state.phase === "drawn" ? privateDraw.card : null,
    peek:
      ((state.phase === "peek" && !p.session.ready.includes(p.userId)) ||
        (state.caller !== null && state.phase === "turn")) &&
      peek?.round === state.round_no
        ? peek.cards
        : null,
    busy: busy || p.busy,
    message,
    act,
  };
}
